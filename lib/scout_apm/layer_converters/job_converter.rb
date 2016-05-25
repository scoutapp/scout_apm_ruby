# Queue/Critical (implicit count)
#   Job/PasswordResetJob Scope=Queue/Critical (implicit count, & total time)
#     JobMetric/Latency 10 Scope=Job/PasswordResetJob
#     ActiveRecord/User/find Scope=Job/PasswordResetJob
#     ActiveRecord/Message/find Scope=Job/PasswordResetJob
#     HTTP/request Scope=Job/PasswordResetJob
#     View/message/text Scope=Job/PasswordResetJob
#       ActiveRecord/Config/find Scope=View/message/text

module ScoutApm
  module LayerConverters
    class JobConverter < ConverterBase
      def call
        return unless request.job?

        JobRecord.new(
          queue_layer.name,
          job_layer.name,
          job_layer.total_call_time,
          job_layer.total_exclusive_time,
          errors,
          create_metrics
        )
      end

      def queue_layer
        @queue_layer ||= find_first_layer_of_type("Queue")
      end

      def job_layer
        @job_layer ||= find_first_layer_of_type("Job")
      end

      def errors
        if request.error?
          1
        else
          0
        end
      end

      def find_first_layer_of_type(layer_type)
        walker.walk do |layer|
          return layer if layer.type == layer_type
        end
      end

      # Full metrics from this request. These get aggregated in Store for the
      # overview metrics, or stored permanently in a SlowTransaction
      # Some merging of metrics will happen here, so if a request calls the same
      # ActiveRecord or View repeatedly, it'll get merged.
      def create_metrics
        metric_hash = Hash.new

        meta_options = {:scope => job_layer.legacy_metric_name}

        walker.walk do |layer|
          next if layer == job_layer
          next if layer == queue_layer
          next if layer.annotations[:ignorable]

          # we don't need to use the full metric name for scoped metrics as we
          # only display metrics aggregrated by type, just use "ActiveRecord"
          # or similar.
          metric_name = layer.type

          meta = MetricMeta.new(metric_name, meta_options)
          metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )

          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
        end

        # Add the latency metric, which wasn't stored as a distinct layer
        latency = request.annotations[:queue_latency] || 0
        meta = MetricMeta.new("Latency", meta_options)
        stat = MetricStats.new
        stat.update!(latency)
        metric_hash[meta] = stat

        metric_hash
      end
    end
  end
end
