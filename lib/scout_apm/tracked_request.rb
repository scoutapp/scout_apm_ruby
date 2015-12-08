# A TrackedRequest is a stack of layers, where completed layers (go into, then
# come out of a layer) are forgotten as they finish. Layers are attached to
# their children as the process goes, building a tree structure within the
# layer objects. When the last layer is finished (hence the whole request is
# finished) it hands the root layer off to be recorded.

module ScoutApm
  class TrackedRequest
    # Context is application defined extra information.  (ie, which user, what
    # is their email/ip, what plan are they on, what locale are they using,
    # etc) See documentation for examples on how to set this from a
    # before_filter
    attr_reader :context

    # The first layer registered with this request. All other layers will be
    # children of this layer.
    attr_reader :root_layer

    def initialize
      @layers = []
      @annotations = {}
      @ignoring_children = false
      @controller_reached = false
      @context = Context.new
      @root_layer = nil
    end

    def start_layer(layer)
      @root_layer = layer unless @root_layer # capture root layer

      ScoutApm::Agent.instance.logger.info("Starting Layer: #{layer.to_s}")
      @layers[-1].add_child(layer) if @layers.any?
      @layers.push(layer)
    end

    def stop_layer
      layer = @layers.pop
      layer.record_stop_time!
      ScoutApm::Agent.instance.logger.info("Stopping Layer: #{layer.to_s}")

      if finalized?
        record!
      end
    end

    ###################################
    # Annotations
    ###################################

    # As we learn things about this request, we can add data here.
    # For instance, when we know where Rails routed this request to, we can store that scope info.
    # Or as soon as we know which URI it was directed at, we can store that.
    #
    # This data is internal to ScoutApm, to add custom information, use the Context api.
    def annotate_request(hsh)
      @annotations.merge!(hsh)
    end

    # Delegate an annotation into the currently running layer
    #
    # Store specific information about the specific layer here.
    # For instance, {:sql => "SELECT * FROM users"} in an ActiveRecord layer
    def annotate_layer(*args)
      @layers[-1].annotate_layer(*args)
    end

    ###################################
    # Persist the Request
    ###################################

    # After finishishing a request, it needs to be persisted, and combined with
    # other requests, eventually to be sent up to ScoutApm's server.

    # Are we finished with this request?
    # We're done if we have no layers left after popping one off
    def finalized?
      @layers.none?
    end

    # TODO: Which object translates a request obj into a recorded & merged set of objects
    def record!
      @recorded = true
      metrics = LayerMetricConverter.new(self).call
      ScoutApm::Agent.instance.store.track!(metrics)

      # require 'pp'
      # ScoutApm::Agent.instance.logger.info("Finished Request, Metrics: #{metrics.pretty_inspect}")

      # slow_requests = LayerConverter.new()
    end

    # Have we already persisted this request?
    def recorded?
      @recorded
    end

    # Allow us to skip this request if it didn't actually hit a controller at
    # any point (for instance if it was initiated from booting rails, or other
    # uses of ActiveRecord and such
    def controller_reached!
      @controller_reached = true
    end

    def controller_reached?
      @controller_reached
    end

    ###################################
    # Ignoring Children
    ###################################

    # Enable this when you would otherwise double track something interesting.
    # This came up when we implemented InfluxDB instrumentation, which is more
    # specific, and useful than the fact that InfluxDB happens to use Net::HTTP
    # internally
    #
    # When enabled, new layers won't be added to the current Request.

    def ignore_children!
      @ignoring_children = true
    end

    def acknowledge_children!
      @ignoring_children = false
    end
  end
end
