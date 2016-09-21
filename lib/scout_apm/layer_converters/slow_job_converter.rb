module ScoutApm
  module LayerConverters
    class SlowJobConverter < ConverterBase
      def initialize(*)
        super

        # After call to super, so @request is populated
        @points = if request.job?
                    ScoutApm::Agent.instance.slow_job_policy.score(request)
                  else
                    -1
                  end

        setup_subscopable_callbacks
      end

      def name
        request.unique_name
      end

      def score
        @points
      end

      def call
        return nil unless request.job?
        return nil unless queue_layer
        return nil unless job_layer

        ScoutApm::Agent.instance.slow_job_policy.stored!(request)

        # record the change in memory usage
        mem_delta = ScoutApm::Instruments::Process::ProcessMemory.rss_to_mb(request.capture_mem_delta!)

        timing_metrics, allocation_metrics = create_metrics

        unless ScoutApm::Instruments::Allocations::ENABLED
          allocation_metrics = {}
        end

        SlowJobRecord.new(
          queue_layer.name,
          job_layer.name,
          root_layer.stop_time,
          job_layer.total_call_time,
          job_layer.total_exclusive_time,
          request.context,
          timing_metrics,
          allocation_metrics,
          mem_delta,
          job_layer.total_allocations,
          score,
          limited?
        )
      end

      def queue_layer
        @queue_layer ||= find_first_layer_of_type("Queue")
      end

      def job_layer
        @job_layer ||= find_first_layer_of_type("Job")
      end

      def skip_layer?(layer)
        super(layer) || layer == queue_layer
      end

      def create_metrics
        metric_hash = Hash.new
        allocation_metric_hash = Hash.new

        walker.walk do |layer|
          next if skip_layer?(layer)

          # The queue_layer is useful to capture for other reasons, but doesn't
          # create a MetricMeta/Stat of its own
          next if layer == queue_layer

          store_specific_metric(layer, metric_hash, allocation_metric_hash)
          store_aggregate_metric(layer, metric_hash, allocation_metric_hash)
        end

        metric_hash = attach_backtraces(metric_hash)
        allocation_metric_hash = attach_backtraces(allocation_metric_hash)

        [metric_hash, allocation_metric_hash]
      end
    end
  end
end
