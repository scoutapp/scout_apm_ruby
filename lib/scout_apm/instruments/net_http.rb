module ScoutApm
  module Instruments
    class NetHttp
      attr_reader :context

      def initialize(context)
        @context = context
        @installed = false
      end

      def logger
        context.logger
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        if defined?(::Net) && defined?(::Net::HTTP)
          logger.info "Instrumenting Net::HTTP"

          ::Net::HTTP.class_eval do
            include ScoutApm::Tracer

            def request_with_scout_instruments(*args,&block)
              self.class.instrument("HTTP", "request", :desc => request_scout_description(args.first)) do
                request_without_scout_instruments(*args, &block)
              end
            end

            def request_scout_description(req)
              path = req.path
              path = path.path if path.respond_to?(:path)
              (@address + path.split('?').first)[0..99]
            end

            alias request_without_scout_instruments request
            alias request request_with_scout_instruments
          end
        end
      end
    end
  end
end
