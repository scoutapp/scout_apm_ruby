module ScoutApm
  class LayerConverterBase
    attr_reader :walker
    attr_reader :request
    attr_reader :root_layer

    def initialize(request)
      @request = request
      @root_layer = request.root_layer
      @walker = LayerDepthFirstWalker.new(root_layer)
    end

    # Scope is determined by the first Controller we hit.  Most of the time
    # there will only be 1 anyway.  But if you have a controller that calls
    # another controller method, we may pick that up:
    #     def update
    #       show
    #       render :update
    #     end
    def scope_layer
      @scope_layer ||= walker.walk do |layer|
        if layer.type == "Controller"
          break layer
        end
      end
    end

  end

  # Take a TrackedRequest and turn it into a hash of:
  #   MetricMeta => MetricStats
  # This will do some merging of metrics as duplicate calls are seen.
  class LayerMetricConverter < LayerConverterBase
    def call
      scope = scope_layer

      # TODO: Track requests that never reach a Controller (for example, when
      # Middleware decides to return rather than passing onward)
      return {} unless scope

      create_metrics
    end

    # Full metrics from this request. These get aggregated in Store for the
    # overview metrics, or stored permanently in a SlowTransaction
    # Some merging of metrics will happen here, so if a request calls the same
    # ActiveRecord or View repeatedly, it'll get merged.
    def create_metrics
      metric_hash = Hash.new

      walker.walk do |layer|
        meta_options = if layer == scope_layer # We don't scope the controller under itself
                         {}
                       else
                         {:scope => scope_layer.legacy_metric_name}
                       end

        meta_options.merge!(:desc => layer.desc) if layer.desc

        meta = MetricMeta.new(layer.legacy_metric_name, meta_options)
        meta.extra.merge!(:backtrace => layer.backtrace) if layer.backtrace
        metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )

        stat = metric_hash[meta]
        stat.update!(layer.total_call_time, layer.total_exclusive_time)
      end

      metric_hash
    end
  end

  class LayerErrorConverter < LayerConverterBase
    def call
      scope = scope_layer

      # Should we mark a request as errored out if a middleware raises?
      # How does that interact w/ a tool like Sentry or Honeybadger?
      return {} unless scope
      return {} unless request.error?

      meta = MetricMeta.new("Errors/#{scope.legacy_metric_name}", {})
      stat = MetricStats.new
      stat.update!(1)

      { meta => stat }
    end
  end

  # Take a TrackedRequest and turn it into a slow transaction if needed
  # return a 2 element array, [ Slow Transaction or Nil ,  Hash of metrics to store ]
  class LayerSlowTransactionConverter < LayerConverterBase
    def call
      policy = ScoutApm::Agent.instance.slow_request_policy.capture_type(root_layer.total_call_time)

      case policy
      when ScoutApm::SlowRequestPolicy::CAPTURE_SUMMARY
        return [nil, {}]
      when ScoutApm::SlowRequestPolicy::CAPTURE_NONE
        return [nil, {}]
      end

      scope = scope_layer
      return [nil, {}] unless scope

      uri = request.annotations[:uri] || ""

      metrics = create_metrics
      # Disable stackprof output for now
      stackprof = [] # request.stackprof

      meta = MetricMeta.new("SlowTransactions/all")
      stat = MetricStats.new
      stat.update!(1)

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
        if record_specific_metric?(layer.type)
          meta_options.merge!(:desc => layer.desc) if layer.desc
          meta = MetricMeta.new(layer.legacy_metric_name, meta_options)
          meta.extra.merge!(:backtrace => layer.backtrace) if layer.backtrace
          metric_hash[meta] ||= MetricStats.new( meta_options.has_key?(:scope) )
          stat = metric_hash[meta]
          stat.update!(layer.total_call_time, layer.total_exclusive_time)
        end

        # Merged Metric (no specifics, just sum up by type)
        meta = MetricMeta.new("#{layer.type}/all")
        metric_hash[meta] ||= MetricStats.new(false)
        stat = metric_hash[meta]
        stat.update!(layer.total_call_time, layer.total_exclusive_time)
      end

      metric_hash
    end

    SKIP_SPECIFICS = ["Middleware"]
    # For metrics that are known to be of sort duration (Middleware right now), we don't record specifics on each call to eliminate a metric explosion.
    # There can be many Middlewares in an app.
    def record_specific_metric?(name)
      !SKIP_SPECIFICS.include?(name)
    end
  end

  class LayerDepthFirstWalker
    attr_reader :root_layer

    def initialize(root_layer)
      @root_layer = root_layer
    end

    def before(&block)
      @before_block = block
    end

    def after(&block)
      @after_block = block
    end

    def walk(layer=root_layer, &block)
      layer.children.each do |child|
        @before_block.call(child) if @before_block
        yield child
        walk(child, &block)
        @after_block.call(child) if @after_block
      end
      nil
    end

    # Do this w/o using recursion, since it's prone to stack overflows
    # Takes a block to run over each layer
    # def walk
      # layer_stack = [root_layer]

      # while layer_stack.any?
        # current_layer = layer_stack.pop
        # current_layer.children.reverse.each { |child| layer_stack.push(child) }

        # yield current_layer
      # end
    # end
  end
end
