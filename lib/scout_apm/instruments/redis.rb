module ScoutApm
  module Instruments
    class Redis
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

        if defined?(::Redis) && defined?(::Redis::Client)
          ScoutApm::Agent.instance.logger.info "Instrumenting Redis"

          ::Redis::Client.class_eval do
            include ScoutApm::Tracer

            def call_with_scout_instruments(*args, &block)
              command = args.first.first rescue "Unknown"

              self.class.instrument("Redis", command) do
                call_without_scout_instruments(*args, &block)
              end
            end

            alias_method :call_without_scout_instruments, :call
            alias_method :call, :call_with_scout_instruments
          end
        end
      end
    end
  end
end
