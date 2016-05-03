module ScoutApm
  module LayerConverters
    class AllocationMetricConverter < ConverterBase
      def call
        scope = scope_layer

        # Should we mark a request as errored out if a middleware raises?
        # How does that interact w/ a tool like Sentry or Honeybadger?
        return {} unless scope

        meta = MetricMeta.new("ObjectAllocations", {:scope => scope.legacy_metric_name})
        stat = MetricStats.new
        stat.update!(root_layer.total_allocations)

        { meta => stat }
      end
    end
  end
end
