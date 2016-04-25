module ScoutApm
  module LayerConverters
    class ErrorConverter < ConverterBase
      def call
        scope = scope_layer

        # Should we mark a request as errored out if a middleware raises?
        # How does that interact w/ a tool like Sentry or Honeybadger?
        return {} unless scope
        return {} unless request.error?

        meta = MetricMeta.new("Errors/#{scope.legacy_metric_name}", {})
        stat = MetricStats.new
        stat.update!(1)

        { meta => stat }
      end
    end
  end
end
