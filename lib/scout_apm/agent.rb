module ScoutApm
  # The agent gathers performance data from a Ruby application. One Agent instance is created per-Ruby process. 
  #
  # Each Agent object creates a worker thread (unless monitoring is disabled or we're forking). 
  # The worker thread wakes up every +Agent#period+, merges in-memory metrics w/those saved to disk, 
  # saves tshe merged data to disk, and sends it to the Scout server.
  class Agent
    # see self.instance
    @@instance = nil 
    
    # Accessors below are for associated classes
    attr_accessor :store
    attr_accessor :layaway
    attr_accessor :config
    attr_accessor :environment
    attr_accessor :capacity
    attr_accessor :logger
    attr_accessor :log_file # path to the log file
    attr_accessor :options # options passed to the agent when +#start+ is called.
    attr_accessor :metric_lookup # Hash used to lookup metric ids based on their name and scope
    
    # All access to the agent is thru this class method to ensure multiple Agent instances are not initialized per-Ruby process. 
    def self.instance(options = {})
      @@instance ||= self.new(options)
    end
    
    # Note - this doesn't start instruments or the worker thread. This is handled via +#start+ as we don't 
    # want to start the worker thread or install instrumentation if (1) disabled for this environment (2) a worker thread shouldn't
    # be started (when forking).
    def initialize(options = {})
      @started = false
      @options ||= options
      @store = ScoutApm::Store.new
      @layaway = ScoutApm::Layaway.new
      @config = ScoutApm::Config.new(options[:config_path])
      @metric_lookup = Hash.new
      @process_cpu=ScoutApm::Instruments::Process::ProcessCpu.new(environment.processors)
      @process_memory=ScoutApm::Instruments::Process::ProcessMemory.new
      @capacity = ScoutApm::Capacity.new
    end
    
    def environment
      @environment ||= ScoutApm::Environment.new
    end
    
    # This is called via +ScoutApm::Agent.instance.start+ when ScoutApm is required in a Ruby application.
    # It initializes the agent and starts the worker thread (if appropiate).
    def start(options = {})
      @options.merge!(options)
      init_logger
      logger.info "Attempting to start Scout Agent [#{ScoutApm::VERSION}] on [#{environment.hostname}]"
      if !config.value('monitor') and !@options[:force]
        logger.warn "Monitoring isn't enabled for the [#{environment.env}] environment."
        return false
      elsif !config.value('name')
        logger.warn "An application name is required. Specify the :name value in scout_apm.yml. Not starting agent."
        return false
      elsif !environment.app_server
        logger.warn "Couldn't find a supported app server. Not starting agent."
        return false
      elsif started?
        logger.warn "Already started agent."
        return false
      end
      @started = true
      logger.info "Starting monitoring for [#{config.value('name')}]. Framework [#{environment.framework}] App Server [#{environment.app_server}]."
      start_instruments
      if !start_background_worker?
        logger.debug "Not starting worker thread. Will start worker loops after forking."
        install_passenger_events if environment.app_server == :passenger
        install_unicorn_worker_loop if environment.app_server == :unicorn
        install_rainbows_worker_loop if environment.app_server == :rainbows
        install_puma_worker_loop if environment.app_server == :puma
        return
      end
      start_background_worker
      handle_exit
      logger.info "Scout Agent [#{ScoutApm::VERSION}] Initialized"
    end
    
    # at_exit, calls Agent#shutdown to wrapup metric reporting.
    def handle_exit
      if environment.sinatra? || environment.jruby? || environment.rubinius?
        logger.debug "Exit handler not supported"
      else
        at_exit do 
          logger.debug "Shutdown!"
          # MRI 1.9 bug drops exit codes.
          # http://bugs.ruby-lang.org/issues/5218
          if environment.ruby_19?
            status = $!.status if $!.is_a?(SystemExit)
            shutdown
            exit status if status
          else
            shutdown
          end
        end # at_exit
      end
    end
    
    # Called via an at_exit handler, it (1) stops the background worker and (2) runs it a final time. 
    # The final run ensures metrics are stored locally to the layaway / reported to scoutapp.com. Otherwise,
    # in-memory metrics would be lost and a gap would appear on restarts.
    def shutdown
      return if !started?
      @background_worker.stop
      @background_worker.run_once
    end
    
    def started?
      @started
    end
    
    def gem_root
      File.expand_path(File.join("..","..",".."), __FILE__)
    end
    
    # The worker thread will automatically start UNLESS:
    # * A supported application server isn't detected (example: running via Rails console)
    # * A supported application server is detected, but it forks. In this case, 
    #   the agent is started in the forked process.
    def start_background_worker?
      !environment.forking? or environment.app_server == :thin # clarify why Thin is here but not WEBrick
    end

    ## TODO - Likely possible to unify starting the worker loop in forking servers by listening for the first transaction 
    ## to start and starting the background worker then in that process.
    
    def install_passenger_events
      PhusionPassenger.on_event(:starting_worker_process) do |forked|
        logger.debug "Passenger is starting a worker process. Starting worker thread."
        self.class.instance.start_background_worker
      end
      # The agent's at_exit hook doesn't run when a Passenger process stops. 
      # This does run when a process stops.
      PhusionPassenger.on_event(:stopping_worker_process) do
        logger.debug "Passenger is stopping a worker process, shutting down the agent."
        ScoutApm::Agent.instance.shutdown
      end
    end
    
    def install_unicorn_worker_loop
      logger.debug "Installing Unicorn worker loop."
      Unicorn::HttpServer.class_eval do
        old = instance_method(:worker_loop)
        define_method(:worker_loop) do |worker|
          ScoutApm::Agent.instance.start_background_worker
          old.bind(self).call(worker)
        end
      end
    end
    
    def install_rainbows_worker_loop
      logger.debug "Installing Rainbows worker loop."
      Rainbows::HttpServer.class_eval do
        old = instance_method(:worker_loop)
        define_method(:worker_loop) do |worker|
          ScoutApm::Agent.instance.start_background_worker
          old.bind(self).call(worker)
        end
      end
    end

    def install_puma_worker_loop
      Puma.cli_config.options[:before_worker_boot] << Proc.new do
        logger.debug "Installing Puma worker loop."
        ScoutApm::Agent.instance.start_background_worker
      end
    rescue
      logger.warn "Unable to install Puma worker loop: #{$!.message}"
    end    
    
    # Creates the worker thread. The worker thread is a loop that runs continuously. It sleeps for +Agent#period+ and when it wakes,
    # processes data, either saving it to disk or reporting to Scout.
    def start_background_worker
      logger.debug "Creating worker thread."
      @background_worker = ScoutApm::BackgroundWorker.new
      @background_worker_thread = Thread.new do
        @background_worker.start { process_metrics }
      end # thread new
      logger.debug "Done creating worker thread."
    end
    
    # Called from #process_metrics, which is run via the background worker. 
    def run_samplers
      begin
        cpu_util=@process_cpu.run # returns a hash
        logger.debug "Process CPU: #{cpu_util.inspect} [#{environment.processors} CPU(s)]"
        store.track!("CPU/Utilization",cpu_util,:scope => nil) if cpu_util
      rescue => e
        logger.info "Error reading ProcessCpu"
        logger.debug e.message
        logger.debug e.backtrace.join("\n")
      end

      begin
        mem_usage=@process_memory.run # returns a single number, in MB
        logger.debug "Process Memory: #{mem_usage}MB"
        store.track!("Memory/Physical",mem_usage,:scope => nil) if mem_usage
      rescue => e
        logger.info "Error reading ProcessMemory"
        logger.debug e.message
        logger.debug e.backtrace.join("\n")
      end
    end
    
    # Loads the instrumention logic.
    def load_instruments
      case environment.framework
      when :rails
        require File.expand_path(File.join(File.dirname(__FILE__),'instruments/rails/action_controller_instruments.rb'))
      when :rails3_or_4
        require File.expand_path(File.join(File.dirname(__FILE__),'instruments/rails3_or_4/action_controller_instruments.rb'))
      end
      require File.expand_path(File.join(File.dirname(__FILE__),'instruments/active_record_instruments.rb'))
      require File.expand_path(File.join(File.dirname(__FILE__),'instruments/net_http.rb'))
      require File.expand_path(File.join(File.dirname(__FILE__),'instruments/moped_instruments.rb'))
      require File.expand_path(File.join(File.dirname(__FILE__),'instruments/mongoid_instruments.rb'))
    rescue
      logger.warn "Exception loading instruments:"
      logger.warn $!.message
      logger.warn $!.backtrace
    end
    
    # Injects instruments into the Ruby application.
    def start_instruments
      logger.debug "Installing instrumentation"
      load_instruments
    end
    
  end # class Agent
end # module ScoutApm