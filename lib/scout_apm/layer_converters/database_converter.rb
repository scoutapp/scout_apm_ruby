module ScoutApm
  module LayerConverters
    class DatabaseConverter < ConverterBase
      def call
        scope = scope_layer

        # TODO: Track requests that never reach a Controller (for example, when
        # Middleware decides to return rather than passing onward)
        return {} unless scope

        create_database_metrics
      end

      def create_database_metrics
        metric_ary = Array.new

        walker.walk do |layer|
          next if skip_layer?(layer) || layer.annotations.nil?
          metric_ary << layer if layer.type == 'ActiveRecord'
        end
        metric_ary
      end
    end
  end
end
