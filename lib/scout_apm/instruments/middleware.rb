module ScoutApm
  module Instruments
    class Middleware
      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        if defined?(ActionDispatch) && defined?(ActionDispatch::MiddlewareStack) && defined?(ActionDispatch::MiddlewareStack::Middleware)
          ActionDispatch::MiddlewareStack::Middleware.class_eval do
            def build(app)
              ScoutApm::Agent.instance.logger.info("Building Middleware #{klass.name}")
              new_mw = klass.new(app, *args, &block)
              MiddlewareWrapper.new(new_mw, klass.name)
            end
          end
        end
      end

      class MiddlewareWrapper
        def initialize(app, name)
          @app = app
          @type = "Middleware"
          @name = name
        end

        def call(env)
          req = ScoutApm::RequestManager.lookup
          req.start_layer( ScoutApm::Layer.new(@type, @name) )
          @app.call(env)
        ensure
          req.stop_layer
        end
      end
    end
  end
end
