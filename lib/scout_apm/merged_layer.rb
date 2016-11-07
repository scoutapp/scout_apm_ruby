module ScoutApm
  # A MergedLayer is a lossy-compression approach to fall back on once we max out
  # the number of detailed layer objects we store.  See LayerChildrenSet for the
  # logic on when that change over happens
  #
  # QUESTION: What do we do if we attempt to merge an item that has children?
  class MergedLayer
    attr_reader :type

    def initialize(type)
      @type = type

      @total_call_time = 0
      @total_exclusive_time = 0
      @total_allocations = 0
      @total_exclusive_allocations = 0
      @total_layers = 0
    end

    def absorb(layer)
      @total_layers += 1

      @total_call_time += layer.total_call_time
      @total_exclusive_time += layer.total_exclusive_time

      @total_allocations += layer.total_allocations
      @total_exclusive_allocations += layer.total_exclusive_allocations
    end

    def total_call_time
      @total_call_time
    end

    def total_exclusive_time
      @total_exclusive_time
    end

    def total_allocations
      @total_allocations
    end

    def total_exclusive_allocations
      @total_exclusive_allocations
    end

    def count
      @total_layers
    end

    # This is the old style name. This function is used for now, but should be
    # removed, and the new type & name split should be enforced through the
    # app.
    def legacy_metric_name
      "#{type}/Merged"
    end

    def children
      Set.new
    end

    def annotations
      nil
    end

    def to_s
      "<MergedLayer type=#{type} count=#{count}>"
    end

    ######################################################
    #  Stub out some methods with static default values  #
    ######################################################
    def subscopable?
      false
    end

    def desc
      nil
    end

    def backtrace
      nil
    end


    #######################################################################
    #  Many methods don't make any sense on a merged layer. Raise errors  #
    #  aggressively for now to detect mistaken calls                      #
    #######################################################################

    def add_child
      raise "Should never call add_child on a merged_layer"
    end

    def record_stop_time!(*)
      raise "Should never call record_stop_time! on a merged_layer"
    end

    def record_allocations!
      raise "Should never call record_allocations! on a merged_layer"
    end

    def desc=(*)
      raise "Should never call desc on a merged_layer"
    end

    def annotate_layer(*)
      raise "Should never call annotate_layer on a merged_layer"
    end

    def subscopable!
      raise "Should never call subscopable! on a merged_layer"
    end

    def capture_backtrace!
      raise "Should never call capture_backtrace on a merged_layer"
    end

    def caller_array
      raise "Should never call caller_array on a merged_layer"
    end
  end
end
