module ScoutApm
  module LayerConverters
    class AllocationMetricConverter < ConverterBase
      def call
        scope = scope_layer
        return {} unless scope && ScoutApm::Instruments::Allocations::ENABLED

        meta = MetricMeta.new("ObjectAllocations", {:scope => scope.legacy_metric_name})
        stat = MetricStats.new
        stat.update!(root_layer.total_allocations)

        { meta => stat }
      end
    end
  end
end
