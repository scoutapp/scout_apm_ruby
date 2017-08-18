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
        metric_ary = Array.new

        walker.walk do |layer|
          next if skip_layer?(layer) || layer.annotations.nil?
          metric_ary << layer if layer.type == 'ActiveRecord'
        end
        metric_ary
      end

      def db_query_metric_set_from_layers(database_layers)
        DbQueryMetricSet.new.absorb_layers!(database_layers)
      end
    end
  end
end
