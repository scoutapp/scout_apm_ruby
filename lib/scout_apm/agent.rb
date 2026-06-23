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

      logger.info "Scout Agent [#{ScoutApm::VERSION}] Initialized"

      # Hook fork() so the agent's threads are never left alive across a fork
      # (the cause of intermittent worker-boot deadlocks under forking servers).
      ScoutApm::ForkSafety.install

      if should_load_instruments? || force
        instrument_manager.install!
        install_background_job_integrations
        install_app_server_integration
      else
        logger.info "Not Loading Instruments"
      end

      logger.info "Scout Agent [#{ScoutApm::VERSION}] Installed"

      context.installed!

      @preconditions = ScoutApm::Agent::Preconditions.new
      if @preconditions.check?(context) || force
        start
      end
    end

    # Unconditionally starts the agent. This includes verifying instruments are
    # installed, and starting the background worker.
    #
    # The monitor precondition is checked explicitly, and we will *never* start with monitor = false
    #
    # This does not attempt to start twice
    def start(opts={})
      return unless context.config.value('monitor')

      if context.started?
        start_background_worker unless background_worker_running?
        start_error_service_background_worker if error_service_enabled? && !error_service_background_worker_running?
        return
      end

      install unless context.installed?

      instrument_manager.install! if should_load_instruments?

      context.started!

      log_environment

      # Save it into a variable to prevent it from ever running twice
      @app_server_load ||= AppServerLoad.new(context).run

      start_background_worker
      start_error_service_background_worker if error_service_enabled?
    end

    def instrument_manager
      @instrument_manager ||= ScoutApm::InstrumentManager.new(context)
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

    # Attempts to install all background job integrations. This can come up if
    # an app has both Resque and Sidekiq - we want both to be installed if
    # possible, it's no harm to have the "wrong" one also installed while running.
    def install_background_job_integrations
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

    # monitor is the key configuration here. If it is true, then we want the
    # instruments. If it is false, we mostly don't want them, unless you're
    # asking for devtrace (ie. not reporting to apm servers as a real app, but
    # only for local browsers).
    def should_load_instruments?
      return true if context.config.value('dev_trace')
      context.config.value('monitor')
    end

    ###############
    #  Fork hooks #
    ###############

    # Called (via ScoutApm::ForkSafety) on the parent side just before fork().
    # Tears down every agent-owned thread *fast* (no graceful join / flush -- a
    # join could block on an in-flight request and we must not be mid-operation
    # when fork() runs). The recorder is reset so the child rebuilds it lazily.
    def stop_threads_for_fork
      logger.debug "[ForkSafety] Stopping agent threads before fork (pid #{Process.pid})" if background_worker_running?

      if @app_server_load && @app_server_load.respond_to?(:stop)
        @app_server_load.stop
      end
      @app_server_load = nil

      @background_worker.stop if @background_worker
      @background_worker_thread.kill if @background_worker_thread && @background_worker_thread.alive?
      @background_worker_thread = nil

      @error_service_background_worker.stop if @error_service_background_worker
      @error_service_background_worker_thread.kill if @error_service_background_worker_thread && @error_service_background_worker_thread.alive?
      @error_service_background_worker_thread = nil

      context.reset_recorder_for_fork!
    end

    # Called on both the parent and the child after fork() returns. Restarts the
    # agent's threads so each process has a fresh, working set. No-op unless the
    # agent had already started (and monitoring is on).
    def restart_after_fork
      return unless context.started?
      return unless context.config.value('monitor')

      logger.debug "[ForkSafety] Restarting agent threads after fork (pid #{Process.pid})"

      @app_server_load = AppServerLoad.new(context).run
      start_background_worker(true)
      start_error_service_background_worker if error_service_enabled?
    end

    #################################
    #  Background Worker Lifecycle  #
    #################################

    # Creates the worker thread. The worker thread is a loop that runs continuously. It sleeps for +Agent#period+ and when it wakes,
    # processes data, either saving it to disk or reporting to Scout.
    # => true if thread & worker got started
    # => false if it wasn't started (either due to already running, or other preconditions)
    def start_background_worker(quiet=false)
      if !context.config.value('monitor')
        logger.debug "Not starting background worker as monitoring isn't enabled." unless quiet
        return false
      end

      if background_worker_running?
        logger.info "Not starting background worker, already started" unless quiet
        return false
      end

      if context.shutting_down?
        logger.info "Not starting background worker, already in process of shutting down" unless quiet
        return false
      end

      logger.info "Initializing worker thread."

      # Install once per process. at_exit blocks are inherited across fork, so a
      # forked child already has the handler and must not stack another one.
      unless @exit_handler_installed
        ScoutApm::Agent::ExitHandler.new(context).install
        @exit_handler_installed = true
      end

      periodic_work = ScoutApm::PeriodicWork.new(context)

      @background_worker = ScoutApm::BackgroundWorker.new(context)
      begin
        @background_worker_thread = Thread.new do
          @background_worker.start {
            periodic_work.run
          }
        end
      rescue ThreadError => e
        logger.warn "Unable to start background worker thread: #{e.message}. Metrics will not be reported from this process."
        @background_worker = nil
        @background_worker_thread = nil
        return false
      end

      return true
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

    # seconds to batch error reports
    ERROR_SEND_FREQUENCY = 5
    def start_error_service_background_worker
      return false if error_service_background_worker_running?

      periodic_work = ScoutApm::ErrorService::PeriodicWork.new(context)

      @error_service_background_worker = ScoutApm::BackgroundWorker.new(context, ERROR_SEND_FREQUENCY)
      begin
        @error_service_background_worker_thread = Thread.new do
          @error_service_background_worker.start {
            periodic_work.run
          }
        end
      rescue ThreadError => e
        logger.warn "Unable to start error service worker thread: #{e.message}. Errors will not be reported from this process."
        @error_service_background_worker = nil
        @error_service_background_worker_thread = nil
        return false
      end

      return true
    end

    def error_service_enabled?
      context.config.value('errors_enabled')
    end

    def error_service_background_worker_running?
      @error_service_background_worker_thread          &&
        @error_service_background_worker_thread.alive? &&
        @error_service_background_worker               &&
        @error_service_background_worker.running?
    end
  end
end
