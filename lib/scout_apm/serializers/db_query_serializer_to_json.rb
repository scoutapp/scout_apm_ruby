module ScoutApm
  module Serializers
    class DbQuerySerializerToJson
      attr_reader :db_query_metrics

      def initialize(db_query_metrics)
        @db_query_metrics = db_query_metrics
      end

      def as_json
        db_query_metrics.map{|_k, v| v.as_json }
      end
    end
  end
end
