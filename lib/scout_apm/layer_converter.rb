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

    # Full metrics from this request. These get aggregated in Store for the
    # overview metrics, or stored permanently in a SlowTransaction
    # Some merging of metrics will happen here, so if a request calls the same
    # ActiveRecord or View repeatedly, it'll get merged.
    def create_metrics
      metric_hash = Hash.new

      scope_name = scope_layer.legacy_metric_name

      walker.walk do |layer|
        meta_options = (scope_name == layer.legacy_metric_name) ? {} : {:scope => scope_name}
        meta_options.merge!(:desc => layer.desc) if layer.desc

        meta = MetricMeta.new(layer.legacy_metric_name, meta_options)
        metric_hash[meta] ||= MetricStats.new(scope_name == layer.legacy_metric_name)

        stat = metric_hash[meta]
        stat.update!(layer.total_call_time, layer.total_exclusive_time)
      end

      metric_hash
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

  # Take a TrackedRequest and turn it into either nil, or a SlowTransaction record
  class LayerSlowTransactionConverter < LayerConverterBase
    SLOW_REQUEST_TIME_THRESHOLD = 2 # seconds

    def call
      return nil unless should_capture_slow_request?

      scope = scope_layer
      return nil unless scope

      uri = request.annotations[:uri] || ""
      SlowTransaction.new(uri,
                          scope.legacy_metric_name,
                          root_layer.total_call_time,
                          create_metrics,
                          request.context,
                          root_layer.stop_time,
                          request.stackprof)
    end

    def should_capture_slow_request?
      root_layer.total_call_time > SLOW_REQUEST_TIME_THRESHOLD
    end
  end

  class LayerBreadthFirstWalker
    attr_reader :root_layer

    def initialize(root_layer)
      @root_layer = root_layer
    end

    # Do this w/o using recursion, since it's prone to stack overflows
    # Takes a block to run over each layer
    def walk
      # Queue, shift of front, push on back
      layer_queue = [root_layer]

      while layer_queue.any?
        current_layer = layer_queue.shift
        current_layer.children.each { |child| layer_queue.push(child) }
        yield current_layer
      end
    end
  end

  class LayerDepthFirstWalker
    attr_reader :root_layer

    def initialize(root_layer)
      @root_layer = root_layer
    end

    # Do this w/o using recursion, since it's prone to stack overflows
    # Takes a block to run over each layer
    def walk
      layer_stack = [root_layer]

      while layer_stack.any?
        current_layer = layer_stack.pop
        current_layer.children.reverse.each { |child| layer_stack.push(child) }
        yield current_layer
      end
    end
  end
end
