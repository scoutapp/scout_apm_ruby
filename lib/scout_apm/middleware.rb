module ScoutApm
  class Middleware
    def initialize(app)
      @app = app
      @started = false
    end

    # If we get a web request in, then we know we're running in some sort of app server
    def call(env)
      ScoutApm::Agent.instance.start(:skip_app_server_check => true) unless @started

      @started = true
      @app.call(env)
    end
  end
end
