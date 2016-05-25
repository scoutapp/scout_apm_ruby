module ScoutApm
  module LayerConverters
    class SlowJobConverter < ConverterBase
      def initialize(*)
        @backtraces = []
        super

        # After call to super, so @request is populated
        @points = if request.job?
                    ScoutApm::Agent.instance.slow_job_policy.score(request)
                  else
                    -1
                  end
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

        SlowJobRecord.new(
          queue_layer.name,
          job_layer.name,
          root_layer.stop_time,
          job_layer.total_call_time,
          job_layer.total_exclusive_time,
          request.context,
          create_metrics,
          score)
      end

      def queue_layer
        @queue_layer ||= find_first_layer_of_type("Queue")
      end

      def job_layer
        @job_layer ||= find_first_layer_of_type("Job")
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
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)

          # Merged Metric (no specifics, just sum up by type)
          meta = MetricMeta.new("#{layer.type}/all")
          metric_hash[meta] ||= MetricStats.new(false)
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
        end

        metric_hash = attach_backtraces(metric_hash)

        metric_hash
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
