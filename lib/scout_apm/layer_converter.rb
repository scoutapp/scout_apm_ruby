module ScoutApm
  # Take a TrackedRequest and turn it into a hash of:
  #   MetricMeta => MetricStats
  # This will do some merging of metrics as duplicate calls are seen.
  class LayerMetricConverter
    def initialize(request)
      @request = request
      @walker = LayerDepthFirstWalker.new(request.root_layer)
    end

    def call
      scope = determine_scope

      # TODO: Track requests that never reach a Controller (for example, when
      # Middleware decides to return rather than passing onward)
      return {} unless scope

      metric_hash = Hash.new { |h, k| h[k] = MetricStats.new }
      walker.walk do |layer|
        meta_options = (scope == layer.legacy_metric_name) ? {} : {:scope => scope}
        meta = MetricMeta.new(layer.legacy_metric_name, meta_options)
        stat = metric_hash[meta] # lookup or create
        stat.update!(layer.total_call_time, layer.total_exclusive_time)
      end

      metric_hash
    end

    private

    attr_reader :walker
    attr_reader :request

    # Scope is determined by the first Controller we hit.  Most of the time
    # there will only be 1 anyway.  But if you have a controller that calls
    # another controller method, we may pick that up:
    #     def update
    #       show
    #       render :update
    #     end
    def determine_scope
      walker.walk do |layer|
        if layer.type == "Controller"
          return layer.legacy_metric_name
        end
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
      # Queue, shift of front, push on back
      layer_queue = [root_layer]

      while layer_queue.any?
        current_layer = layer_queue.shift
        current_layer.children.each { |child| layer_queue.push(child) }
        yield current_layer
      end
    end
  end
end
