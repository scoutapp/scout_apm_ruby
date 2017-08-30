module ScoutApm
  module LayerConverters
    class DatabaseConverter < ConverterBase
      def initialize(*)
        super
        @db_query_metric_set = DbQueryMetricSet.new
      end

      def register_hooks(walker)
        super

        return unless scope_layer

        walker.on do |layer|
          next if skip_layer?(layer)

          stat = DbQueryMetricStats.new(
            layer.name.model,
            layer.name.normalized_operation,
            scope_layer.legacy_metric_name, # controller_scope
            1,
            layer.total_call_time,
            layer.annotations[:record_count])
          @db_query_metric_set << stat
        end
      end

      def skip_layer?(layer)
        super || layer.annotations.nil? || layer.type != 'ActiveRecord'
      end

      def record!
        @store.track_db_query_metrics!(@db_query_metric_set)
      end
    end
  end
end
