module ScoutApm
  class Middleware
    MAX_ATTEMPTS = 5

    def initialize(app)
      @app = app
      @attempts = 0
      @enabled = ScoutApm::Agent.instance.apm_enabled?
      @started = ScoutApm::Agent.instance.started? && ScoutApm::Agent.instance.background_worker_running?
    end

    # If we get a web request in, then we know we're running in some sort of app server
    def call(env)
      if !@enabled || @started || @attempts > MAX_ATTEMPTS
        @app.call(env)
      else
        attempt_to_start_agent
        @app.call(env)
      end
    end

    def attempt_to_start_agent
      @attempts += 1
      ScoutApm::Agent.instance.start(:skip_app_server_check => true)
      ScoutApm::Agent.instance.start_background_worker
      @started = ScoutApm::Agent.instance.started? && ScoutApm::Agent.instance.background_worker_running?
    rescue => e
      # Can't be sure of any logging here, so fall back to ENV var and STDOUT
      if ENV["SCOUT_LOG_LEVEL"] == "debug"
        STDOUT.puts "Failed to start via Middleware: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      end
    end
  end
end
