# Take a TrackedRequest and turn it into a hash of:
#   MetricMeta => MetricStats

module ScoutApm
  module LayerConverters
    class MetricConverter < ConverterBase
      def call
        scope = scope_layer

        # TODO: Track requests that never reach a Controller (for example, when
        # Middleware decides to return rather than passing onward)
        return {} unless scope

        create_metrics
      end

      # Full metrics from this request. These get aggregated in Store for the
      # overview metrics, or stored permanently in a SlowTransaction
      # Some merging of metrics will happen here, so if a request calls the same
      # ActiveRecord or View repeatedly, it'll get merged.
      def create_metrics
        metric_hash = Hash.new

        walker.walk do |layer|
          meta_options = if layer == scope_layer # We don't scope the controller under itself
                          {}
                        else
                          {:scope => scope_layer.legacy_metric_name}
                        end

          # we don't need to use the full metric name for scoped metrics as we only display metrics aggregrated
          # by type.
          metric_name = meta_options.has_key?(:scope) ? layer.type : layer.legacy_metric_name

          meta = MetricMeta.new(metric_name, meta_options)
          metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )

          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
        end
        metric_hash
      end
    end
  end
end
