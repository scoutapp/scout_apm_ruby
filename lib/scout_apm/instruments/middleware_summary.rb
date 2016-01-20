# Inserts a single middleware at the outer edge of the stack (the first
# middleware called, before passing to the rest of the stack) to trace the
# total time spent between all middlewares. This instrument does not attempt to
# allocate time to specific middlewares. (see MiddlewareDetailed)
#
module ScoutApm
  module Instruments
    class MiddlewareSummary
      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        if defined?(ActionDispatch) && defined?(ActionDispatch::MiddlewareStack)
          ScoutApm::Agent.instance.logger.info("Instrumenting Middleware")
          ActionDispatch::MiddlewareStack.class_eval do
            def build_with_scout_instruments(app = nil, &block)
              mw_stack = build_without_scout_instruments(app) { block.call if block }
              MiddlewareSummaryWrapper.new(mw_stack)
            end

            alias_method :build_without_scout_instruments, :build
            alias_method :build, :build_with_scout_instruments
          end
        end
      end

      class MiddlewareSummaryWrapper
        def initialize(app)
          @app = app
        end

        def call(env)
          req = ScoutApm::RequestManager.lookup
          layer = ScoutApm::Layer.new("Middleware", "Summary")
          req.start_layer(layer)
          @app.call(env)
        ensure
          req.stop_layer
        end
      end
    end
  end
end
