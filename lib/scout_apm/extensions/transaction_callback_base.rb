module ScoutApm
  module Extensions
    # This is the Base class that Transaction Callback Extensions should inherit from.
    # It exposes a number of commonly accessed methods and attributes useful for sending to other services.
    # This is called via +TrackedRequest#record!+ and is used by both web and background job transactions.
    class TransactionCallbackBase
      # A Hash that stores the output of each layer converter by name. See the naming conventions in +TrackedRequest+.
      attr_accessor :converter_results

      # A flat hash of the context associated w/this transaction
      attr_accessor :context

      # The scope layer (either a "Controller" or "Job")
      attr_accessor :scope_layer

      def initialize(converter_results,context,scope_layer)
        @converter_results = converter_results
        @context = context.to_flat_hash
        @scope_layer = scope_layer
      end

      def logger
        ScoutApm::Agent.instance.context.logger
      end

      # The total duration of the transaction
      def duration_ms
        scope_layer.total_call_time*1000 # ms
      end

      # The time in queue of the transaction in ms. If not present, +nil+ is returned as this is unknown.
      def queue_time_ms
        # Controller logic
        if converter_results[:queue_time] && converter_results[:queue].any?
          converter_results[:queue_time].values.first.total_call_time*1000 # ms
        # Job logic
        elsif converter_results[:job]
          stat = converter_results[:job].metric_set.metrics[ScoutApm::MetricMeta.new("Latency/all", :scope => scope_layer.legacy_metric_name)]
          stat ? stat.total_call_time*1000 : nil
        else
          nil
        end
      end

      def hostname
        ScoutApm::Agent.instance.context.environment.hostname
      end

      def app_name
        ScoutApm::Agent.instance.context.config.value('name')
      end

      # Returns +true+ if the transaction raised an exception.
      def error?
        converter_results[:errors] && converter_results[:errors].any?
      end

      def transation_type
        scope_layer.type
      end

      # Web/Job are more language-agnostic names for controller/job. For example, Python Django does not have controllers.
      def transaction_type_slug
        case transation_type
        when 'Controller'
          'web'
        when 'Job'
          'job'
        else
          'transaction'
        end
      end
    end
  end
end