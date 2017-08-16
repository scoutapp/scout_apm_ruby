module ScoutApm
  module LayerConverters
    class ErrorConverter < ConverterBase
      def record!
        # Should we mark a request as errored out if a middleware raises?
        # How does that interact w/ a tool like Sentry or Honeybadger?
        return unless scope_layer
        return unless request.error?

        meta = MetricMeta.new("Errors/#{scope_layer.legacy_metric_name}", {})
        stat = MetricStats.new
        stat.update!(1)

        @store.track!({ meta => stat })
      end
    end
  end
end
