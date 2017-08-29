module ScoutApm
  module Serializers
    class DbQuerySerializerToJson
      attr_reader :db_query_metrics

      def initialize(db_query_metrics)
        @db_query_metrics = db_query_metrics
      end

      def as_json
        Hash[db_query_metrics.map(&:as_json)]
      end
    end
  end
end
