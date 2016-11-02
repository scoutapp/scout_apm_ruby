module ScoutApm
  module LayerConverters
    class ConverterBase

      attr_reader :walker
      attr_reader :request
      attr_reader :root_layer

      def initialize(request)
        @request = request
        @root_layer = request.root_layer
        @backtraces = []
        @walker = DepthFirstWalker.new(root_layer)

        @limited = false
      end

      # Scope is determined by the first Controller we hit.  Most of the time
      # there will only be 1 anyway.  But if you have a controller that calls
      # another controller method, we may pick that up:
      #     def update
      #       show
      #       render :update
      #     end
      def scope_layer
        @scope_layer ||= find_first_layer_of_type("Controller") || find_first_layer_of_type("Job")
      end

      def find_first_layer_of_type(layer_type)
        walker.walk do |layer|
          return layer if layer.type == layer_type
        end
      end

      ################################################################################
      # Subscoping
      ################################################################################
      #
      # Keep a list of subscopes, but only ever use the front one.  The rest
      # get pushed/popped in cases when we have many levels of subscopable
      # layers.  This lets us push/pop without otherwise keeping track very closely.
      def setup_subscopable_callbacks
        @subscope_layers = []

        walker.before do |layer|
          if layer.subscopable?
            @subscope_layers.push(layer)
          end
        end

        walker.after do |layer|
          if layer.subscopable?
            @subscope_layers.pop
          end
        end
      end

      def subscoped?(layer)
        @subscope_layers.first && layer != @subscope_layers.first # Don't scope under ourself.
      end

      def subscope_name
        @subscope_layers.first.legacy_metric_name
      end


      ################################################################################
      # Backtrace Handling
      ################################################################################
      #
      # Because we get several layers for the same thing if you call an
      # instrumented thing repeatedly, and only some of them may have
      # backtraces captured, we store the backtraces off into another spot
      # during processing, then at the end, we loop over those saved
      # backtraces, putting them back into the metrics hash.
      #
      # This comes up most often when capturing n+1 backtraces. Because the
      # query may be fast enough to evade our time-limit based backtrace
      # capture, only the Nth item (see TrackedRequest for more detail) has a
      # backtrack captured.  This sequence makes sure that we report up that
      # backtrace in the aggregated set of metrics around that call.

      # Call this as you are processing each layer. It will store off backtraces
      def store_backtrace(layer, meta)
        return unless layer.backtrace

        bt = ScoutApm::Utils::BacktraceParser.new(layer.backtrace).call
        if bt.any?
          meta.backtrace = bt
          @backtraces << meta
        else
          ScoutApm::Agent.instance.logger.debug { "Unable to capture an app-specific backtrace for #{meta.inspect}\n#{layer.backtrace}" }
        end
      end

      # Call this after you finish walking the layers, and want to take the
      # set-aside backtraces and place them into the metas they match
      def attach_backtraces(metric_hash)
        @backtraces.each do |meta_with_backtrace|
          metric_hash.keys.find { |k| k == meta_with_backtrace }.backtrace = meta_with_backtrace.backtrace
        end
        metric_hash
      end


      ################################################################################
      # Limit Handling
      ################################################################################

      # To prevent huge traces from being generated, we should stop collecting
      # detailed metrics as we go beyond some reasonably large count.
      #
      # We should still add up the /all aggregates.

      MAX_METRICS = 500

      def over_metric_limit?(metric_hash)
        if metric_hash.size > MAX_METRICS
          @limited = true
        else
          false
        end
      end

      def limited?
        !! @limited
      end

      ################################################################################
      # Meta Scope
      ################################################################################

      # When we make MetricMeta records, we need to determine a few things from layer.
      def make_meta_options(layer)
        scope_hash = make_meta_options_scope(layer)
        desc_hash = make_meta_options_desc_hash(layer)

        scope_hash.merge(desc_hash)
      end

      def make_meta_options_scope(layer)
        # This layer is scoped under another thing. Typically that means this is a layer under a view.
        # Like: Controller -> View/users/show -> ActiveRecord/user/find
        #   in that example, the scope is the View/users/show
        if subscoped?(layer)
          {:scope => subscope_name}

        # We don't scope the controller under itself
        elsif layer == scope_layer
          {}

        # This layer is a top level metric ("ActiveRecord", or "HTTP" or
        # whatever, directly under the controller), so scope to the
        # Controller
        else
          {:scope => scope_layer.legacy_metric_name}
        end
      end

      def make_meta_options_desc_hash(layer)
        if layer.desc
          {:desc => layer.desc.to_s}
        else
          {}
        end
      end


      ################################################################################
      # Storing metrics into the hashes
      ################################################################################

      # This is the detailed metric - type, name, backtrace, annotations, etc.
      def store_specific_metric(layer, metric_hash, allocation_metric_hash)
        return false if over_metric_limit?(metric_hash)

        meta_options = make_meta_options(layer)

        meta = MetricMeta.new(layer.legacy_metric_name, meta_options)
        meta.extra.merge!(layer.annotations) if layer.annotations

        store_backtrace(layer, meta)

        metric_hash[meta] ||= MetricStats.new(meta_options.has_key?(:scope))
        allocation_metric_hash[meta] ||= MetricStats.new(meta_options.has_key?(:scope))

        # timing
        stat = metric_hash[meta]
        stat.update!(layer.total_call_time, layer.total_exclusive_time)

        # allocations
        stat = allocation_metric_hash[meta]
        stat.update!(layer.total_allocations, layer.total_exclusive_allocations)
      end

      # Merged Metric - no specifics, just sum up by type (ActiveRecord, View, HTTP, etc)
      def store_aggregate_metric(layer, metric_hash, allocation_metric_hash)
          meta = MetricMeta.new("#{layer.type}/all")

          metric_hash[meta] ||= MetricStats.new(false)
          allocation_metric_hash[meta] ||= MetricStats.new(false)

          # timing
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)

          # allocations
          stat = allocation_metric_hash[meta]
          stat.update!(layer.total_allocations, layer.total_exclusive_allocations)
      end

      ################################################################################
      # Misc Helpers
      ################################################################################

      # Sometimes we start capturing a layer without knowing if we really
      # want to make an entry for it.  See ActiveRecord instrumentation for
      # an example. We start capturing before we know if a query is cached
      # or not, and want to skip any cached queries.
      def skip_layer?(layer)
        return false if layer.annotations.nil?
        return true  if layer.annotations[:ignorable]
      end
    end
  end
end
