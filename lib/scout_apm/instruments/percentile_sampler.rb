module ScoutApm
  module Instruments
    class PercentileSampler
      attr_reader :logger

      attr_reader :percentiles

      def initialize(logger, percentiles)
        @logger = logger
        @percentiles = Array(percentiles)
      end

      def human_name
        "Percentiles"
      end

      def metrics
        ms = {}

        ScoutApm::Agent.instance.request_histograms_resettable.each_name do |name|
          percentiles.each do |percentile|
            meta = MetricMeta.new("Percentile/#{percentile}/#{name}")
            stat = MetricStats.new
            stat.update!(ScoutApm::Agent.instance.request_histograms_resettable.quantile(name, percentile))
            ms[meta] = stat
          end
        end

        # Wipe the histograms, get ready for the next minute's worth of data.
        ScoutApm::Agent.instance.request_histograms_resettable.reset_all!

        ms
      end

      private
    end
  end
end
