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
    attr_reader :recorder
    attr_accessor :layaway
    attr_accessor :config
    attr_accessor :logger
    attr_accessor :log_file # path to the log file
    attr_accessor :options # options passed to the agent when +#start+ is called.
    attr_accessor :metric_lookup # Hash used to lookup metric ids based on their name and scope
    attr_reader :slow_request_policy
    attr_reader :slow_job_policy
    attr_reader :process_start_time # used when creating slow transactions to report how far from startup the transaction was recorded.
    attr_reader :ignored_uris

    # Histogram of the cumulative requests since the start of the process
    attr_reader :request_histograms

    # Histogram of the requests, distinct by reporting period (minute)
    # { StoreReportingPeriodTimestamp => RequestHistograms }
    attr_reader :request_histograms_by_time

    # All access to the agent is thru this class method to ensure multiple Agent instances are not initialized per-Ruby process.
    def self.instance(options = {})
      @@instance ||= self.new(options)
    end

    # Note - this doesn't start instruments or the worker thread. This is handled via +#start+ as we don't
    # want to start the worker thread or install instrumentation if (1) disabled for this environment (2) a worker thread shouldn't
    # be started (when forking).
    def initialize(options = {})
      @started = false
      @process_start_time = Time.now
      @options ||= options

      # until the agent is started, there's no recorder
      @recorder = nil

      # Start up without attempting to load a configuration file. We need to be
      # able to lookup configuration options like "application_root" which would
      # then in turn influence where the configuration file came from.
      #
      # Later in initialization, we reset @config to include the file.
      @config = ScoutApm::Config.without_file

      @slow_request_policy = ScoutApm::SlowRequestPolicy.new
      @slow_job_policy = ScoutApm::SlowJobPolicy.new
      @request_histograms = ScoutApm::RequestHistograms.new
      @request_histograms_by_time = Hash.new { |h, k| h[k] = ScoutApm::RequestHistograms.new }

      @store          = ScoutApm::Store.new

      @layaway        = ScoutApm::Layaway.new(config, environment)
      @metric_lookup  = Hash.new

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

      if environment.interactive?
        logger.warn "Agent attempting to load in interactive mode. #{force? ? 'Forcing agent to start' : 'Not starting agent'}"
        return false unless force?
      end

      if app_server_missing?(options) && background_job_missing?
        if force?
          logger.warn "Agent starting (forced)"
        else
          logger.warn "Deferring agent start. Standing by for first request"
        end
        return false unless force?
      end

      if started?
        logger.warn "Already started agent."
        return false
      end

      if defined?(::ScoutRails)
        logger.warn "ScoutAPM is incompatible with the old Scout Rails plugin. Please remove scout_rails from your Gemfile"
        return false unless force?
      end

      true
    end

    # This is called via +ScoutApm::Agent.instance.start+ when ScoutApm is required in a Ruby application.
    # It initializes the agent and starts the worker thread (if appropiate).
    def start(options = {})
      @options.merge!(options)

      @config = ScoutApm::Config.with_file(@config.value("config_file"))
      layaway.config = config

      init_logger
      logger.info "Attempting to start Scout Agent [#{ScoutApm::VERSION}] on [#{environment.hostname}]"

      @recorder = create_recorder

      @config.log_settings

      @ignored_uris = ScoutApm::IgnoredUris.new(config.value('ignore'))

      load_instruments if should_load_instruments?(options)

      if !@config.any_keys_found?
        logger.info("No configuration file loaded, and no configuration found in ENV. " +
                    "For assistance configuring Scout, visit " +
                    "http://help.apm.scoutapp.com/#configuration-options")
      end

      return false unless preconditions_met?(options)
      @started = true
      logger.info "Starting monitoring for [#{environment.application_name}]. Framework [#{environment.framework}] App Server [#{environment.app_server}] Background Job Framework [#{environment.background_job_name}]."

      [ ScoutApm::Instruments::Process::ProcessCpu.new(environment.processors, logger),
        ScoutApm::Instruments::Process::ProcessMemory.new(logger),
        ScoutApm::Instruments::PercentileSampler.new(logger, request_histograms_by_time),
      ].each { |s| store.add_sampler(s) }

      app_server_load_hook

      if environment.background_job_integration
        environment.background_job_integration.install
        logger.info "Installed Background Job Integration [#{environment.background_job_name}]"
      end

      # start_background_worker? is true on non-forking servers, and directly
      # starts the background worker.  On forking servers, a server-specific
      # hook is inserted to start the background worker after forking.
      if start_background_worker?
        start_background_worker
        logger.info "Scout Agent [#{ScoutApm::VERSION}] Initialized"
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

    def exit_handler_supported?
      if environment.sinatra?
        logger.debug "Exit handler not supported for Sinatra"
        false
      elsif environment.jruby?
        logger.debug "Exit handler not supported for JRuby"
        false
      elsif environment.rubinius?
        logger.debug "Exit handler not supported for Rubinius"
        false
      else
        true
      end
    end

    # at_exit, calls Agent#shutdown to wrapup metric reporting.
    def install_exit_handler
      logger.debug "Shutdown handler not supported" and return unless exit_handler_supported?
      logger.debug "Installing Shutdown Handler"

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

    # Called via an at_exit handler, it:
    # (1) Stops the background worker
    # (2) Stores metrics locally (forcing current-minute metrics to be written)
    # It does not attempt to actually report metrics.
    def shutdown
      logger.info "Shutting down ScoutApm"

      return if !started?

      return if @shutdown
      @shutdown = true

      if @background_worker
        logger.info("Stopping background worker")
        @background_worker.stop
        store.write_to_layaway(layaway, :force)
        if @background_worker_thread.alive?
          @background_worker_thread.wakeup
          @background_worker_thread.join
        end
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
      @background_worker_thread          &&
        @background_worker_thread.alive? &&
        @background_worker               &&
        @background_worker.running?
    end

    # Creates the worker thread. The worker thread is a loop that runs continuously. It sleeps for +Agent#period+ and when it wakes,
    # processes data, either saving it to disk or reporting to Scout.
    def start_background_worker
      if !apm_enabled?
        logger.debug "Not starting background worker as monitoring isn't enabled."
        return false
      end
      logger.info "Not starting background worker, already started" and return if background_worker_running?
      logger.info "Initializing worker thread."

      install_exit_handler

      @recorder = create_recorder
      logger.info("recorder is now: #{@recorder.class}")

      @background_worker = ScoutApm::BackgroundWorker.new
      @background_worker_thread = Thread.new do
        @background_worker.start {
          ScoutApm::Debug.instance.call_periodic_hooks
          ScoutApm::Agent.instance.process_metrics
          clean_old_percentiles
        }
      end
    end

    def clean_old_percentiles
      request_histograms_by_time.
        keys.
        select {|timestamp| timestamp.age_in_seconds > 60 * 10 }.
        each {|old_timestamp| request_histograms_by_time.delete(old_timestamp) }
    end

    # If we want to skip the app_server_check, then we must load it.
    def should_load_instruments?(options={})
      return true if options[:skip_app_server_check]
      return true if config.value('dev_trace')
      return false if !apm_enabled?
      environment.app_server_integration.found? || !background_job_missing?
    end

    # Loads the instrumention logic.
    def load_instruments
      case environment.framework
      when :rails then
        install_instrument(ScoutApm::Instruments::ActionControllerRails2)
      when :rails3_or_4 then
        install_instrument(ScoutApm::Instruments::ActionControllerRails3Rails4)
        install_instrument(ScoutApm::Instruments::RailsRouter)

        if config.value("detailed_middleware")
          install_instrument(ScoutApm::Instruments::MiddlewareDetailed)
        else
          install_instrument(ScoutApm::Instruments::MiddlewareSummary)
        end
      end

      install_instrument(ScoutApm::Instruments::ActionView)
      install_instrument(ScoutApm::Instruments::ActiveRecord)
      install_instrument(ScoutApm::Instruments::Moped)
      install_instrument(ScoutApm::Instruments::Mongoid)
      install_instrument(ScoutApm::Instruments::NetHttp)
      install_instrument(ScoutApm::Instruments::HttpClient)
      install_instrument(ScoutApm::Instruments::Redis)
      install_instrument(ScoutApm::Instruments::InfluxDB)
      install_instrument(ScoutApm::Instruments::Elasticsearch)
      install_instrument(ScoutApm::Instruments::Grape)
    rescue
      logger.warn "Exception loading instruments:"
      logger.warn $!.message
      logger.warn $!.backtrace
    end

    def install_instrument(instrument_klass)
      # Don't attempt to install the same instrument twice
      return if @installed_instruments.any? { |already_installed_instrument| instrument_klass === already_installed_instrument }

      # Allow users to skip individual instruments via the config file
      instrument_short_name = instrument_klass.name.split("::").last
      if (config.value("disabled_instruments") || []).include?(instrument_short_name)
        logger.info "Skipping Disabled Instrument: #{instrument_short_name} - To re-enable, change `disabled_instruments` key in scout_apm.yml"
        return
      end

      instance = instrument_klass.new
      @installed_instruments << instance
      instance.install
    end

    def app_server_missing?(options = {})
      !environment.app_server_integration(true).found? && !options[:skip_app_server_check]
    end

    def background_job_missing?(options = {})
      environment.background_job_integration.nil? && !options[:skip_background_job_check]
    end

    def clear_recorder
      @recorder = nil
    end

    def create_recorder
      if @recorder
        return @recorder
      end

      if config.value("async_recording")
        logger.debug("Using asynchronous recording")
        ScoutApm::BackgroundRecorder.new(logger).start
      else
        logger.debug("Using synchronous recording")
        ScoutApm::SynchronousRecorder.new(logger).start
      end
    end

    def start_remote_server(bind, port)
      return if @remote_server && @remote_server.running?

      logger.info("Starting Remote Agent Server")

      # Start the listening web server only in parent process.
      @remote_server = ScoutApm::Remote::Server.new(
        bind,
        port,
        ScoutApm::Remote::Router.new(ScoutApm::SynchronousRecorder.new(logger), logger),
        logger
      )

      @remote_server.start
    end

    # Execute this in the child process of a remote agent. The parent is
    # expected to have its accepting webserver up and running
    def use_remote_recorder(host, port)
      logger.debug("Becoming Remote Agent (reporting to: #{host}:#{port})")
      @recorder = ScoutApm::Remote::Recorder.new(host, port, logger)
      @store = ScoutApm::FakeStore.new
    end
  end
end
