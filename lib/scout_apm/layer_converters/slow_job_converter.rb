module ScoutApm
  module LayerConverters
    class SlowJobConverter < ConverterBase
      def initialize(*)
        @backtraces = []
        super
      end

      def call
        return unless request.job?

        job_name = [queue_layer.name, job_layer.name]

        slow_enough = ScoutApm::Agent.instance.slow_job_policy.slow?(job_name, root_layer.total_call_time)
        return unless slow_enough

        # record the change in memory usage
        mem_delta = ScoutApm::Instruments::Process::ProcessMemory.rss_to_mb(request.capture_mem_delta!)

        timing_metrics, allocation_metrics = create_metrics

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
          job_layer.total_allocations
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
        metric_hash = Hash.new
        allocation_metric_hash = Hash.new

        # Keep a list of subscopes, but only ever use the front one.  The rest
        # get pushed/popped in cases when we have many levels of subscopable
        # layers.  This lets us push/pop without otherwise keeping track very closely.
        subscope_layers = []

        walker.before do |layer|
          if layer.subscopable?
            subscope_layers.push(layer)
          end
        end

        walker.after do |layer|
          if layer.subscopable?
            subscope_layers.pop
          end
        end

        walker.walk do |layer|
          # Sometimes we start capturing a layer without knowing if we really
          # want to make an entry for it.  See ActiveRecord instrumentation for
          # an example. We start capturing before we know if a query is cached
          # or not, and want to skip any cached queries.
          next if layer.annotations[:ignorable]

          # The queue_layer is useful to capture for other reasons, but doesn't
          # create a MetricMeta/Stat of its own
          next if layer == queue_layer

          meta_options = if subscope_layers.first && layer != subscope_layers.first # Don't scope under ourself.
                           subscope_name = subscope_layers.first.legacy_metric_name
                           {:scope => subscope_name}
                         elsif layer == job_layer # We don't scope the controller under itself
                           {}
                         else
                           {:scope => job_layer.legacy_metric_name}
                         end

          # Specific Metric
          meta_options.merge!(:desc => layer.desc.to_s) if layer.desc
          meta = MetricMeta.new(layer.legacy_metric_name, meta_options)
          meta.extra.merge!(layer.annotations)

          if layer.backtrace
            bt = ScoutApm::Utils::BacktraceParser.new(layer.backtrace).call
            if bt.any? # we could walk thru the call stack and not find in-app code
              meta.backtrace = bt
              # Why not just call meta.backtrace and call it done? The walker could access a later later that generates the same MetricMeta but doesn't have a backtrace. This could be
              # lost in the metric_hash if it is replaced by the new key.
              @backtraces << meta
            else
              ScoutApm::Agent.instance.logger.debug { "Unable to capture an app-specific backtrace for #{meta.inspect}\n#{layer.backtrace}" }
            end
          end

          metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )
          allocation_metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
          stat = allocation_metric_hash[meta]
          stat.update!(layer.total_allocations, layer.total_exclusive_allocations)

          # Merged Metric (no specifics, just sum up by type)
          meta = MetricMeta.new("#{layer.type}/all")
          metric_hash[meta] ||= MetricStats.new(false)
          allocation_metric_hash[meta] ||= MetricStats.new(false)
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
          stat = allocation_metric_hash[meta]
          stat.update!(layer.total_allocations, layer.total_exclusive_allocations)
        end

        metric_hash = attach_backtraces(metric_hash)
        allocation_metric_hash = attach_backtraces(allocation_metric_hash)

        [metric_hash,allocation_metric_hash]
      end

      def attach_backtraces(metric_hash)
        @backtraces.each do |meta_with_backtrace|
          metric_hash.keys.find { |k| k == meta_with_backtrace }.backtrace = meta_with_backtrace.backtrace
        end
        metric_hash
      end
    end
  end
end
