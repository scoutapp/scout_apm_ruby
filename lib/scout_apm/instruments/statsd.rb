module ScoutApm
  module Instruments
    class Statsd
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
        if defined?(::Statsd)
          @installed = true

          logger.info "Instrumenting Statsd"

          ::Statsd.class_eval do

            def increment_with_scout_instruments(stat, sample_rate=1)
              apm_store_statsd(stat, 1)
              increment_without_scout_instruments(stat, sample_rate)
            end
            alias_method :increment_without_scout_instruments, :increment
            alias_method :increment, :increment_with_scout_instruments

            def decrement_with_scout_instruments(stat, sample_rate=1)
              apm_store_statsd(stat, -1)
              decrement_without_scout_instruments(stat, sample_rate)
            end
            alias_method :decrement_without_scout_instruments, :decrement
            alias_method :decrement, :decrement_with_scout_instruments

            def count_with_scout_instruments(stat, count, sample_rate=1)
              apm_store_statsd(stat, count)
              count_without_scout_instruments(stat, count, sample_rate)
            end
            alias_method :count_without_scout_instruments, :count
            alias_method :count, :count_with_scout_instruments

            def gauge_with_scout_instruments(stat, value, sample_rate=1)
              apm_store_statsd(stat, value)
              gauge_without_scout_instruments(stat, value, sample_rate)
            end
            alias_method :gauge_without_scout_instruments, :gauge
            alias_method :gauge, :gauge_with_scout_instruments

            def timing_with_scout_instruments(stat, ms, sample_rate=1)
              apm_store_statsd(stat, ms)
              timing_without_scout_instruments(stat, ms, sample_rate)
            end
            alias_method :timing_without_scout_instruments, :timing
            alias_method :timing, :timing_with_scout_instruments

            def time_with_scout_instruments(*args, &block)
              start = Time.now
              res = time_without_scout_instruments(*args, &block)
              apm_store_statsd(args.first, (Time.now - start)*1000)
              res
            end
            alias_method :time_without_scout_instruments, :time
            alias_method :time, :time_with_scout_instruments

            def apm_store_statsd(stat, value)
              ScoutApm::Context.add({"#{stat}" => value})
            end
          end
        end
      end
    end
  end
end
