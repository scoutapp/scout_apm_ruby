module ScoutApm
  module Serializers
    class DbQuerySerializerToJson
      attr_reader :db_query_metrics

      def initialize(db_query_metrics)
        @db_query_metrics = db_query_metrics
      end

      def as_json
        limited_metrics.map{|metric| metric.as_json }
      end

      def limited_metrics
        if over_limit?
          db_query_metrics.
            values.
            sort_by {|stat| stat.call_time }.
            reverse.
            take(limit)
        else
          db_query_metrics.values
        end
      end

      def over_limit?
        db_query_metrics.size > limit
      end

      def limit
        ScoutApm::Agent.instance.config.value('database_metric_report_limit')
      end
    end
  end
end
