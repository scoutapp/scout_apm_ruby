module ScoutApm
  module Instruments
    class NetHttp
      attr_reader :logger

      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        if defined?(::Net) && defined?(::Net::HTTP)
          ScoutApm::Agent.instance.logger.info "Instrumenting Net::HTTP"

          ::Net::HTTP.class_eval do
            include ScoutApm::Tracer

            def request_with_scout_instruments(*args,&block)
              url = (@address + args.first.path.split('?').first)[0..99]
              self.class.instrument("HTTP", "request", :desc => url) do
                request_without_scout_instruments(*args, &block)
              end
            end

            alias request_without_scout_instruments request
            alias request request_with_scout_instruments
          end
        end
      end
    end
  end
end
