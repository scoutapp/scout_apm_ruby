module ScoutApm
  module Instruments
    class HttpClient
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

        if defined?(::HTTPClient)
          ScoutApm::Agent.instance.logger.info "Instrumenting HTTPClient"

          ::HTTPClient.class_eval do
            include ScoutApm::Tracer

            def request_with_scout_instruments(*args, &block)
              method = args[0].to_s
              url = args[1]
              url = url && url.to_s[0..99]

              self.class.instrument("HTTP", method, :desc => url) do
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
