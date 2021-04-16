module ScoutApm
  module Instruments
    class Redis
      attr_reader :context

      def initialize(context)
        @context = context
        @installed = false
      end

      def logger
        context.logger
      end

      def prependable?
        context.environment.supports_module_prepend?
      end

      def installed?
        @installed
      end

      def install
        if defined?(::Redis) && defined?(::Redis::Client)
          @installed = true

          if prependable?
            install_using_prepend
          else
            install_using_tracer
          end
        end
      end

      def install_using_tracer
        logger.info "Instrumenting Redis"

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

      def install_using_prepend
        logger.info "Instrumenting Redis (prepend)"
        ::Redis::Client.prepend(RedisClientInstruments)
      end

      module RedisClientInstruments
        def call(*args, &block)
          req = ScoutApm::RequestManager.lookup

          command = args.first.first rescue "Unknown"

          layer = ScoutApm::Layer.new("Redis", command)
          layer.subscopable!

          begin
            req.start_layer(layer)
            super(*args, &block)
          ensure
            req.stop_layer
          end
        end
      end
    end
  end
end
