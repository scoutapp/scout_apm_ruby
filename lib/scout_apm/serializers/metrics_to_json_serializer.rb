module ScoutApm
  module Serializers
    class MetricsToJsonSerializer
      attr_reader :metrics

      # A hash of meta => stat pairs
      def initialize(metrics)
        @metrics = metrics
      end

      def as_json
        metrics.map{|meta, stat| metric_as_json(meta, stat) }
      end

      def metric_as_json(meta, stat)
        { "bucket" => meta.type,
          "name" => meta.name, # No scope values needed here, since it's implied by the nesting.
          "count" => stat.call_count,
          "total_call_time" => stat.total_call_time,
          "total_exclusive_time" => stat.total_exclusive_time,
          "timings" => {  # Timings represent the percentiles around total_call_time.
            "0" => stat.min_call_time,
            "100" => stat.max_call_time,
            "avg" => stat.total_call_time / stat.call_count.to_f
          }
        }
      end

    end
  end
end


