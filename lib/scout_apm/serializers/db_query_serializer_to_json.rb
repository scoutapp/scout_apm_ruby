module ScoutApm
  module Serializers
    class DbQuerySerializerToJson
      attr_reader :db_query_metrics

      # Jobs is a series of slow job records
      def initialize(db_query_metrics)
        @db_query_metrics = db_query_metrics
      end

      # An array of job records
      def as_json
        db_query_metrics.map(&:to_json)
      end
    end
  end
end
