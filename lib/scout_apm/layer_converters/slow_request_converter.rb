module ScoutApm
  module LayerConverters
    class SlowRequestConverter < ConverterBase
      def call
        scope = scope_layer
        return [nil, {}] unless scope

        policy = ScoutApm::Agent.instance.slow_request_policy.capture_type(root_layer.total_call_time)
        if policy == ScoutApm::SlowRequestPolicy::CAPTURE_NONE
          return [nil, {}]
        end

        # increment the slow transaction count if this is a slow transaction.
        meta = MetricMeta.new("SlowTransaction/#{scope.legacy_metric_name}")
        stat = MetricStats.new
        stat.update!(1)

        @backtraces = [] # An Array of MetricMetas that have a backtrace

        uri = request.annotations[:uri] || ""

        metrics = create_metrics
        # Disable stackprof output for now
        stackprof = [] # request.stackprof

        [
          SlowTransaction.new(uri,
                              scope.legacy_metric_name,
                              root_layer.total_call_time,
                              metrics,
                              request.context,
                              root_layer.stop_time,
                              stackprof),
          { meta => stat }
        ]
      end

      # Iterates over the TrackedRequest's MetricMetas that have backtraces and attaches each to correct MetricMeta in the Metric Hash.
      def attach_backtraces(metric_hash)
        @backtraces.each do |meta_with_backtrace|
          metric_hash.keys.find { |k| k == meta_with_backtrace }.backtrace = meta_with_backtrace.backtrace
        end
        metric_hash
      end

      # Full metrics from this request. These get aggregated in Store for the
      # overview metrics, or stored permanently in a SlowTransaction
      # Some merging of metrics will happen here, so if a request calls the same
      # ActiveRecord or View repeatedly, it'll get merged.
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
          meta_options = if subscope_layers.first && layer != subscope_layers.first # Don't scope under ourself.
                           subscope_name = subscope_layers.first.legacy_metric_name
                           {:scope => subscope_name}
                         elsif layer == scope_layer # We don't scope the controller under itself
                           {}
                         else
                           {:scope => scope_layer.legacy_metric_name}
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
              ScoutApm::Agent.instance.logger.debug "Unable to capture an app-specific backtrace for #{meta.inspect}\n#{layer.backtrace}"
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
    end
  end
end
