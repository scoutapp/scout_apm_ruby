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

    # As we go through a request, instrumentation can mark more general data into the Request
    # Known Keys:
    #   :uri - the full URI requested by the user
    attr_reader :annotations

    # Nil until the request is finalized, at which point it will hold the
    # entire raw stackprof output for this request
    attr_reader :stackprof

    # Headers as recorded by rails
    # Can be nil if we never reach a Rails Controller
    attr_reader :headers

    def initialize
      @layers = []
      @annotations = {}
      @ignoring_children = false
      @context = Context.new
      @root_layer = nil
      @stackprof = nil
      @error = false
    end

    def start_layer(layer)
      start_request(layer) unless @root_layer

      # ScoutApm::Agent.instance.logger.info("Starting Layer: #{layer.to_s}")
      @layers[-1].add_child(layer) if @layers.any?
      @layers.push(layer)
    end

    def stop_layer
      layer = @layers.pop
      layer.record_stop_time!

      # Do this here, rather than in the layer because we need this caller. Maybe able to move it?
      if layer.total_exclusive_time > ScoutApm::SlowTransaction::BACKTRACE_THRESHOLD
        layer.store_backtrace(ScoutApm::SlowTransaction.backtrace_parser(caller))
      end

      if finalized?
        stop_request
      end
    end

    ###################################
    # Request Lifecycle
    ###################################

    # Are we finished with this request?
    # We're done if we have no layers left after popping one off
    def finalized?
      @layers.none?
    end

    # Run at the beginning of the whole request
    #
    # * Capture the first layer as the root_layer
    # * Start Stackprof
    def start_request(layer)
      @root_layer = layer unless @root_layer # capture root layer
      StackProf.start(:mode => :wall, :interval => ScoutApm::Agent.instance.config.value("stackprof_interval"))
    end

    # Run at the end of the whole request
    #
    # * Collect stackprof info
    # * Send the request off to be stored
    def stop_request
      # ScoutApm::Agent.instance.logger.debug("stop_request: #{annotations[:uri]}" )
      StackProf.stop
      @stackprof = StackProf.results

      record!
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

    # This request had an exception.  Mark it down as an error
    def error!
      @error = true
    end

    def error?
      @error
    end

    def set_headers(headers)
      @headers = headers
    end

    ###################################
    # Persist the Request
    ###################################

    # Convert this request to the appropriate structure, then report it into
    # the peristent Store object
    def record!
      @recorded = true

      metrics = LayerMetricConverter.new(self).call
      ScoutApm::Agent.instance.store.track!(metrics)

      slow, slow_metrics = LayerSlowTransactionConverter.new(self).call
      ScoutApm::Agent.instance.store.track_slow_transaction!(slow)
      ScoutApm::Agent.instance.store.track!(slow_metrics)

      error_metrics = LayerErrorConverter.new(self).call
      ScoutApm::Agent.instance.store.track!(error_metrics)

      queue_time_metrics = RequestQueueTime.new(self).call
      ScoutApm::Agent.instance.store.track!(queue_time_metrics)
    end

    # Have we already persisted this request?
    # Used to know when we should just create a new one (don't attempt to add
    # data to an already-recorded request). See RequestManager
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
