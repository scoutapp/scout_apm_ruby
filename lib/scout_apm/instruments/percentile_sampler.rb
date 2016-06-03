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

      # Gets the 95th%ile for the time requested
      def metrics(time)
        ms = {}
        histos = ScoutApm::Agent.instance.request_histograms_by_time[time]
        histos.each_name do |name|
          percentiles.each do |percentile|
            meta = MetricMeta.new("Percentile/#{percentile}/#{name}")
            stat = MetricStats.new
            stat.update!(histos.quantile(name, percentile))
            ms[meta] = stat
          end
        end

        # Wipe the histograms we just collected data on
        ScoutApm::Agent.instance.request_histograms_by_time.delete(time)

        ms
      end
    end
  end
end
