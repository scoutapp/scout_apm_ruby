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
        metric_hash = Hash.new

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
          meta.extra.merge!(:backtrace => ScoutApm::SlowTransaction.backtrace_parser(layer.backtrace)) if layer.backtrace
          metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)

          # Merged Metric (no specifics, just sum up by type)
          meta = MetricMeta.new("#{layer.type}/all")
          metric_hash[meta] ||= MetricStats.new(false)
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
        end

        metric_hash
      end
    end
  end
end
