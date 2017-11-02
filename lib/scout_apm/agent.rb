module ScoutApm
  # The entry-point for the ScoutApm Agent.
  #
  # Only one Agent instance is created per-Ruby process, and it coordinates the lifecycle of the monitoring.
  #   - initializes various data stores
  #   - coordinates configuration & logging
  #   - starts background threads, running periodically
  #   - installs shutdown hooks
  class Agent
    # see self.instance
    @@instance = nil

    attr_reader :context

    attr_accessor :options # options passed to the agent when +#start+ is called.

    attr_reader :instrument_manager

    # All access to the agent is thru this class method to ensure multiple Agent instances are not initialized per-Ruby process.
    def self.instance(options = {})
      @@instance ||= self.new(options)
    end

    # First call of the agent. Does very little so that the object can be created, and exist.
    def initialize(options = {})
      @options = options
      @context = ScoutApm::AgentContext.new
    end

    def logger
      context.logger
    end

    # Finishes setting up the instrumentation, configuration, and attempts to start the agent.
    def install(force=false)
      context.config = ScoutApm::Config.with_file(context, context.config.value("config_file"))

      context.logger.info "Scout Agent [#{ScoutApm::VERSION}] Initialized"

      @instrument_manager = ScoutApm::InstrumentManager.new(context)
      @instrument_manager.install! if should_load_instruments? || force

      install_background_job_integration
      install_app_server_integration

      # XXX: Should this happen at application start?
      # Should this ever happen after fork?
      # We start a thread in this, which can screw stuff up when we then fork.
      AppServerLoad.new(context).run

      logger.info "Scout Agent [#{ScoutApm::VERSION}] installed"

      context.installed!

      if ScoutApm::Agent::Preconditions.check?(context) || force
        start
      end
    end

    # Unconditionally starts the agent. This includes verifying instruments are
    # installed, and starting the background worker.
    #
    # Does not attempt to start twice.
    def start
      return if context.started?
      install unless context.installed?

      context.started!

      log_environment

      start_background_worker
    end

    def log_environment
      bg_names = context.environment.background_job_integrations.map{|bg| bg.name }.join(", ")

      logger.info(
        "Scout Agent [#{ScoutApm::VERSION}] starting for [#{context.environment.application_name}] " +
        "Framework [#{context.environment.framework}] " +
        "App Server [#{context.environment.app_server}] " +
        "Background Job Framework [#{bg_names}] " +
        "Hostname [#{context.environment.hostname}]"
      )
    end

    def install_background_job_integration
      context.environment.background_job_integrations.each do |int|
        int.install
        logger.info "Installed Background Job Integration [#{int.name}]"
      end
    end

    # This sets up the background worker thread to run at the correct time,
    # either immediately, or after a fork into the actual unicorn/puma/etc
    # worker
    def install_app_server_integration
      context.environment.app_server_integration.install
      logger.info "Installed Application Server Integration [#{context.environment.app_server}]."
    end

    # If true, the agent will start regardless of safety checks.
    def force?
      @options[:force]
    end

    # The worker thread will automatically start UNLESS:
    # * A supported application server isn't detected (example: running via Rails console)
    # * A supported application server is detected, but it forks. In this case,
    #   the agent is started in the forked process.
    def start_background_worker?
      return true if force?
      return !context.environment.forking?
    end

    def should_load_instruments?
      return true if context.config.value('dev_trace')
      # XXX: If monitor is true, we want to install, right?
      # return false if context.config.value('monitor')
      context.environment.app_server_integration.found? || context.environment.background_job_integration
    end

    #################################
    #  Background Worker Lifecycle  #
    #################################

    def start_background_worker
      if !context.config.value('monitor')
        logger.debug "Not starting background worker as monitoring isn't enabled."
        return false
      end

      if background_worker_running?
        logger.info "Not starting background worker, already started"
        return
      end

      logger.info "Initializing worker thread."

      ScoutApm::Agent::ExitHandler.new(context).install

      periodic_work = ScoutApm::PeriodicWork.new(context)

      @background_worker = ScoutApm::BackgroundWorker.new(context)
      @background_worker_thread = Thread.new do
        @background_worker.start {
          periodic_work.run
        }
      end
    end

    def stop_background_worker
      if @background_worker
        logger.info("Stopping background worker")
        @background_worker.stop
        context.store.write_to_layaway(context.layaway, :force)
        if @background_worker_thread.alive?
          @background_worker_thread.wakeup
          @background_worker_thread.join
        end
      end
    end

    def background_worker_running?
      @background_worker_thread          &&
        @background_worker_thread.alive? &&
        @background_worker               &&
        @background_worker.running?
    end
  end
end
