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
            1,                              # count, this is a single query, so 1
            layer.total_call_time,
            records_returned(layer)
          )
          @db_query_metric_set << stat
        end
      end

      def skip_layer?(layer)
        super || layer.type != 'ActiveRecord'
      end

      def record!
        # Everything in the metric set here is from a single transaction, which
        # we want to keep track of. (One web call did a User#find 10 times, but
        # only due to 1 http request)
        @db_query_metric_set.increment_transaction_count!
        @store.track_db_query_metrics!(@db_query_metric_set)
      end

      def records_returned(layer)
        if layer.annotations
          layer.annotations.fetch(:record_count, 0)
        else
          0
        end
      end
    end
  end
end
