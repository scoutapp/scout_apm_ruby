module ScoutApm
  module LayerConverters
    class DatabaseConverter < ConverterBase
      def call
        scope = scope_layer

        # TODO: Track requests that never reach a Controller (for example, when
        # Middleware decides to return rather than passing onward)
        return {} unless scope

        db_query_metric_set_from_layers(select_database_layers)
      end

      def select_database_layers
        db_layers = Array.new

        walker.walk do |layer|
          next if skip_layer?(layer) || layer.annotations.nil?
          db_layers << layer if layer.type == 'ActiveRecord'
        end
        db_layers
      end

      # Takes an array of ActiveRecord layers, creates new DbQueryMetricStats and combines
      # them into a new DbQueryMetricSet.
      # This might be a bit much overhead. Make a new method that can report/combine the raw numbers without
      # the intermediate creation of a DbQueryMetricStats object
      def db_query_metric_set_from_layers(database_layers)
        db_query_metric_set = DbQueryMetricSet.new
        database_layers.each do |l|
          db_query_metric_stats = DbQueryMetricStats.new(l.name.model, l.name.normalized_operation, 1, l.total_call_time, l.annotations[:record_count])
          db_query_metric_set.combine!(db_query_metric_stats)
        end
        db_query_metric_set
      end
    end
  end
end
