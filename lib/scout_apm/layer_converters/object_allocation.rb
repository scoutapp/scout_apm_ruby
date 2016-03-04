module ScoutApm
  module LayerConverters
    # Object Allocation metrics for this request. These have the same format as timing metrics - only aggregrates of 
    # the layer#type are stored.
    class ObjectAllocation < LayerConverterBase
      PREFIX = "ObjectAllocations/".freeze
      def call
        scope = scope_layer

        return {} unless scope

        create_metrics
      end

      # Almost the same as +LayerMetricConverter#create_metrics+. Differences:
      # * prefix metric_name w/ "ObjectAllocations/"
      # * update stats w/ +layer.object_allocations+ vs. call times.
      def create_metrics
        metric_hash = Hash.new

        walker.walk do |layer|
          meta_options = if layer == scope_layer # We don't scope the controller under itself
                           {}
                         else
                           {:scope => PREFIX+scope_layer.legacy_metric_name}
                         end

          metric_name = meta_options.has_key?(:scope) ? layer.type : PREFIX+layer.legacy_metric_name

          meta = MetricMeta.new(metric_name, meta_options)
          metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )

          stat = metric_hash[meta]
          # calling state#update! and passing in allocations as time makes server-side metric queries involved. this is handled easier.
          stat.call_count += layer.object_allocations 
        end
        metric_hash
      end
    end
  end
end