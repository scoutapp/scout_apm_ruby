module ScoutApm
  module Instruments
    class Memcached
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
        if defined?(::Dalli) && defined?(::Dalli::Client)
          @installed = true

          logger.info "Instrumenting Memcached"

          ::Dalli::Client.class_eval do
            include ScoutApm::Tracer

            def perform_with_scout_instruments(*args, &block)
              command = args.first rescue "Unknown"

              self.class.instrument("Memcached", command) do
                perform_without_scout_instruments(*args, &block)
              end
            end

            alias_method :perform_without_scout_instruments, :perform
            alias_method :perform, :perform_with_scout_instruments
          end
        end
      end
    end
  end
end
