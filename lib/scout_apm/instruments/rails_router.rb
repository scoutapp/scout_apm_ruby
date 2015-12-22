module ScoutApm
  module Instruments
    class RailsRouter
      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        if defined?(ActionDispatch) && defined?(ActionDispatch::Routing) && defined?(ActionDispatch::Routing::RouteSet)
          ActionDispatch::Routing::RouteSet.class_eval do
            def call_with_scout_instruments(*args)
              req = ScoutApm::RequestManager.lookup
              req.start_layer(ScoutApm::Layer.new("Router", "Rails"))

              begin
                call_without_scout_instruments(*args)
              ensure
                req.stop_layer
              end
            end

            alias call_without_scout_instruments call
            alias call call_with_scout_instruments
          end
        end
      end
    end
  end
end
