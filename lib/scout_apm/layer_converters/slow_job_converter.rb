module ScoutApm
  module LayerConverters
    class SlowJobConverter < ConverterBase
      def call
        return unless request.job?

        job_name = [queue_layer.name, job_layer.name]

        slow_enough = ScoutApm::Agent.instance.slow_job_policy.slow?(job_name, root_layer.total_call_time)
        return unless slow_enough

        SlowJobRecord.new(
          queue_layer.name,
          job_layer.name,
          job_layer.total_call_time,
          job_layer.total_exclusive_time,
          create_metrics,
        )
      end

      def queue_layer
        @queue_layer ||= find_first_layer_of_type("Queue")
      end

      def job_layer
        @job_layer ||= find_first_layer_of_type("Job")
      end

      def find_first_layer_of_type(layer_type)
        walker.walk do |layer|
          return layer if layer.type == layer_type
        end
      end

      def create_metrics
        {}
      end
    end
  end
end
