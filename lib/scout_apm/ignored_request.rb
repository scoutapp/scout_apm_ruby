# A "fake" class that can be used in place of TrackedRequest, but this ignores all tracing.  This still manages the
# count of layers being added & removed, so it knows when it is "finished", but otherwise does no recording of layers,
# and no recording at completion.
#
# This set via RequestManager.ignore_request! at any point during a request to begin ignoring from that point onward.
#

module ScoutApm
  class IgnoredRequest
    attr_reader :depth

    # Important: Don't capture the tracked_request variable. It needs to be GC'd soon.
    def self.from_tracked_request(tracked_request)
      depth = tracked_request.layer_count
      new(depth)
    end

    def self.from_nothing
      new(0)
    end

    def initialize(initial_layer_depth)
      @depth = initial_layer_depth
    end

    def start_layer(*)
      @depth += 1
    end

    def stop_layer(*)
      @depth -= 1
    end

    # Something odd happened if this is negative, but be safe.
    def recorded?
      depth <= 0
    end

    def layer_count
      depth
    end

    ################################################################################
    # Other unoverriden methods:
    #
    # Use monkey patching to define all the methods that TrackedRequest
    # implements that aren't explicitly defined above.  Use define_method
    # instead of method_missing, since these are called often, and should be as
    # fast as feasible.
    ################################################################################

    # TrackedRequest needs to be required before this class, so we can reference its constant

    (TrackedRequest.instance_methods(false) - self.instance_methods(false)).each do |method|
      define_method method do |*args|
        # noop
      end
    end
  end
end
