module ScoutApm
  module LayerConverters
    class ExternalServiceConverter < ConverterBase
      def initialize(*)
        super
        @external_service_metric_set = ExternalServiceMetricSet.new(context)
      end

      def register_hooks(walker)
        super

        return unless scope_layer

        walker.on do |layer|
          next if skip_layer?(layer)
          stat = ExternalServiceMetricStats.new(
            domain_name(layer),
            operation_name(layer),
            scope_layer.legacy_metric_name, # controller_scope
            1,                              # count, this is a single query, so 1
            layer.total_call_time
          )
          @external_service_metric_set << stat
        end
      end

      def record!
        # Everything in the metric set here is from a single transaction, which
        # we want to keep track of. (One web call did a User#find 10 times, but
        # only due to 1 http request)
        @external_service_metric_set.increment_transaction_count!
        @store.track_external_service_metrics!(@external_service_metric_set)

        nil # not returning anything in the layer results ... not used
      end

      def skip_layer?(layer)
        layer.type != 'Http' ||
          layer.limited? ||
          super
      end

      private


      # If we can't name the domain name, default to:
      DEFAULT_MODEL = "Other"

      # If we can't name the operation, default to:
      DEFAULT_OPERATION = "other"

      def domain_name(layer)
        layer.name.to_s.split("/").first || DEFAULT_MODEL
      end

      def operation_name(layer)
        layer.name.to_s.split("/")[1] || DEFAULT_OPERATION
      end
    end
  end
end
