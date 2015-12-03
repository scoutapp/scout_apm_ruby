# A TrackedRequest is a stack of layers, where completed layers (go into, the
# come out of a layer) are forgotten at this level. When finished it hands the
# root layer off to be recorded
#

module ScoutApm
  class TrackedRequest
    # Context is application defined extra information.
    # (ie, which user, what is their email/ip, what plan are they on, what locale are they using, etc)
    # See documentation for examples on how to set this from a before_filter
    attr_reader :context

    def initialize
      @layers = []
      @annotations = {}
      @ignoring_children = false
      @context = Context.new
    end

    def start_layer(layer)
      return if @ignoring_children

      ScoutApm::Agent.instance.logger.info("Starting Layer: #{layer.to_s}")
      @layers[-1].add_child(layer) if @layers.any?
      @layers.push(layer)
    end

    def stop_layer
      layer = @layers.pop
      layer.record_stop_time!
      ScoutApm::Agent.instance.logger.info("Stopping Layer: #{layer.to_s}")

      if finalized?
        record!(layer)
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
    def record!(root_layer)
      @recorded = true
      ScoutApm::Agent.instance.logger.info("Finished Request, Recording Root Layer: #{root_layer}")
    end

    def recorded?
      @recorded
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
