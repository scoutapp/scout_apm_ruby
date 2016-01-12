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
    attr_accessor :capacity
    attr_accessor :logger
    attr_accessor :log_file # path to the log file
    attr_accessor :options # options passed to the agent when +#start+ is called.
    attr_accessor :metric_lookup # Hash used to lookup metric ids based on their name and scope
    attr_reader :slow_request_policy

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
      @config = ScoutApm::Config.new(options[:config_path])

      @store          = ScoutApm::Store.new
      @layaway        = ScoutApm::Layaway.new
      @metric_lookup  = Hash.new

      @slow_request_policy = ScoutApm::SlowRequestPolicy.new

      @capacity       = ScoutApm::Capacity.new
      @installed_instruments = []
    end

    def environment
      ScoutApm::Environment.instance
    end

    def apm_enabled?
      config.value('monitor')
    end

    # If true, the agent will start regardless of safety checks. Currently just used for testing.
    def force?
      @options[:force]
    end

    def preconditions_met?(options={})
      if !apm_enabled?
        logger.warn "Monitoring isn't enabled for the [#{environment.env}] environment. #{force? ? 'Forcing agent to start' : 'Not starting agent'}"
        return false unless force?
      end

      if !environment.application_name
        logger.warn "An application name could not be determined. Specify the :name value in scout_apm.yml. #{force? ? 'Forcing agent to start' : 'Not starting agent'}."
        return false unless force?
      end

      if app_server_missing?(options) && background_job_missing?
        logger.warn "Couldn't find a supported app server or background job framework. #{force? ? 'Forcing agent to start' : 'Not starting agent'}."
        return false unless force?
      end

      if started?
        logger.warn "Already started agent."
        return false
      end

      if defined?(::ScoutRails)
        logger.warn "ScoutAPM is incompatible with the old Scout Rails plugin. Please remove scout_rails from your Gemfile"
        return false
      end

      true
    end

    # This is called via +ScoutApm::Agent.instance.start+ when ScoutApm is required in a Ruby application.
    # It initializes the agent and starts the worker thread (if appropiate).
    def start(options = {})
      @options.merge!(options)
      init_logger
      logger.info "Attempting to start Scout Agent [#{ScoutApm::VERSION}] on [#{environment.hostname}]"

      if environment.deploy_integration
        logger.info "Starting monitoring for [#{environment.deploy_integration.name}]]."
        return environment.deploy_integration.install
      end
      return false unless preconditions_met?(options)
      @started = true
      logger.info "Starting monitoring for [#{environment.application_name}]. Framework [#{environment.framework}] App Server [#{environment.app_server}] Background Job Framework [#{environment.background_job_name}]."

      load_instruments if should_load_instruments?(options)

      @samplers = [
        ScoutApm::Instruments::Process::ProcessCpu.new(environment.processors, logger),
        ScoutApm::Instruments::Process::ProcessMemory.new(logger)
      ]

      app_server_load_hook

      # start_background_worker? is true on non-forking servers, and directly
      # starts the background worker.  On forking servers, a server-specific
      # hook is inserted to start the background worker after forking.
      if start_background_worker?
        start_background_worker
        handle_exit
        logger.info "Scout Agent [#{ScoutApm::VERSION}] Initialized"
      elsif environment.background_job_integration
        environment.background_job_integration.install
        logger.info "Scout Agent [#{ScoutApm::VERSION}] loaded in [#{environment.background_job_name}] master process. Monitoring will start after background job framework forks its workers."
      else
        environment.app_server_integration.install
        logger.info "Scout Agent [#{ScoutApm::VERSION}] loaded in [#{environment.app_server}] master process. Monitoring will start after server forks its workers."
      end
    end

    # Sends a ping to APM right away, smoothes out onboarding
    # Collects up any relevant info (framework, app server, system time, ruby version, etc)
    def app_server_load_hook
      AppServerLoad.new.run
    end

    def exit_handler_unsupported?
      environment.sinatra? || environment.jruby? || environment.rubinius?
    end

    # at_exit, calls Agent#shutdown to wrapup metric reporting.
    def handle_exit
      logger.debug "Exit handler not supported" and return if exit_handler_unsupported?

      at_exit do
        logger.info "Shutting down Scout Agent"
        # MRI 1.9 bug drops exit codes.
        # http://bugs.ruby-lang.org/issues/5218
        if environment.ruby_19?
          status = $!.status if $!.is_a?(SystemExit)
          shutdown
          exit status if status
        else
          shutdown
        end
      end
    end

    # Called via an at_exit handler, it (1) stops the background worker and (2) runs it a final time.
    # The final run ensures metrics are stored locally to the layaway / reported to scoutapp.com. Otherwise,
    # in-memory metrics would be lost and a gap would appear on restarts.
    def shutdown
      return if !started?
      if @background_worker
        @background_worker.stop
        @background_worker.run_once
      end
    end

    def started?
      @started
    end

    # The worker thread will automatically start UNLESS:
    # * A supported application server isn't detected (example: running via Rails console)
    # * A supported application server is detected, but it forks. In this case,
    #   the agent is started in the forked process.
    def start_background_worker?
      return true if environment.app_server == :thin
      return true if environment.app_server == :webrick
      return true if force?
      return !environment.forking?
    end

    def background_worker_running?
      !! @background_worker_thread
    end

    # Creates the worker thread. The worker thread is a loop that runs continuously. It sleeps for +Agent#period+ and when it wakes,
    # processes data, either saving it to disk or reporting to Scout.
    def start_background_worker
      logger.info "Not starting background worker, already started" and return if background_worker_running?
      logger.info "Initializing worker thread."
      @background_worker = ScoutApm::BackgroundWorker.new
      @background_worker_thread = Thread.new do
        @background_worker.start {
          # First, run periodic samplers. These should run once a minute,
          # rather than per-request. "CPU Load" and similar.
          run_samplers
          capacity.process

          ScoutApm::Agent.instance.process_metrics
        }
      end
    end

    # If we want to skip the app_server_check, then we must load it.
    def should_load_instruments?(options={})
      return true if options[:skip_app_server_check]
      environment.app_server_integration.found? || !background_job_missing?
    end

    # Loads the instrumention logic.
    def load_instruments
      if !background_job_missing?
        case environment.background_job_name
        when :delayed_job
          install_instrument(ScoutApm::Instruments::DelayedJob)
        end
      else
        case environment.framework
        when :rails       then install_instrument(ScoutApm::Instruments::ActionControllerRails2)
        when :rails3_or_4 then
          install_instrument(ScoutApm::Instruments::ActionControllerRails3)
          install_instrument(ScoutApm::Instruments::Middleware)
          install_instrument(ScoutApm::Instruments::RailsRouter)
        when :sinatra     then install_instrument(ScoutApm::Instruments::Sinatra)
        end
      end

      install_instrument(ScoutApm::Instruments::ActiveRecord)
      install_instrument(ScoutApm::Instruments::Moped)
      install_instrument(ScoutApm::Instruments::Mongoid)
      install_instrument(ScoutApm::Instruments::NetHttp)

      if StackProf.respond_to?(:fake?) && StackProf.fake?
        logger.info 'StackProf not found - add `gem "stackprof"` to your Gemfile to enable advanced code profiling (only for Ruby 2.1+)'
      end
    rescue
      logger.warn "Exception loading instruments:"
      logger.warn $!.message
      logger.warn $!.backtrace
    end

    def install_instrument(instrument_klass)
      # Don't attempt to install the same instrument twice
      return if @installed_instruments.any? { |already_installed_instrument| instrument_klass === already_installed_instrument }
      instance = instrument_klass.new
      @installed_instruments << instance
      instance.install
    end

    def deploy_integration
      environment.deploy_integration
    end

    # TODO: Extract a proper class / registery for these. They don't really belong here
    def run_samplers
      @samplers.each do |sampler|
        begin
          result = sampler.run
          store.track_one!(sampler.metric_type, sampler.metric_name, result) if result
        rescue => e
          logger.info "Error reading #{sampler.human_name}"
          logger.debug e.message
          logger.debug e.backtrace.join("\n")
        end
      end
    end

    def app_server_missing?(options = {})
      !environment.app_server_integration(true).found? && !options[:skip_app_server_check]
    end

    def background_job_missing?(options = {})
      environment.background_job_integration.nil? && !options[:skip_background_job_check]
    end
  end
end
