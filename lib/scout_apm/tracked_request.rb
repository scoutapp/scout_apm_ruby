# A TrackedRequest is a stack of layers, where completed layers (go into, the
# come out of a layer) are forgotten at this level. When finished it hands the
# root layer off to be recorded
#
# It also manages a Context object for this request.
# (ie, which user, what is their email/ip, what plan are they on, what locale are they using)

module ScoutApm
  class TrackedRequest
    attr_reader :context

    def initialize
      @layers = []
      @context = Context.new
    end

    def start_layer(layer)
      @layers[-1].add_child(layer) if @layers.any?
      @layers.push(layer)
    end

    def stop_layer
      layer = @layers.pop
      layer.record_stop_time!

      if finalized?
        record!(layer)
      end
    end

    # Delegate an annotation into the currently running layer
    def annotate_layer(*args)
      @layers[-1].annotate_layer(*args)
    end

    # We're done if we have no layers left after popping one off
    def finalized?
      @layers.none?
    end

    # TODO: Which object translates a request obj into a recorded & merged set of objects
    def record!(root_layer)
      @recorded = true
    end

    def finished?
      @recorded
    end
  end
end
