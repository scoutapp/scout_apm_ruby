module ScoutApm
  # A set of children records for any given Layer.  This implements some
  # rate-limiting logic.
  #
  # When the set of children is small, keep them unique
  # When the set of children gets large enough, stop keeping details
  #
  # The next optimization, which is not yet implemented:
  #   when the set of children gets larger, attempt to merge them without data loss
  class LayerChildrenSet
    include Enumerable

    # By default, how many unique children of a type do we store before
    # flipping over to storing only aggregate info.
    DEFAULT_UNIQUE_CUTOFF = 1000
    attr_reader :unique_cutoff

    # The Set of children objects
    attr_reader :children
    private :children


    def initialize(unique_cutoff = DEFAULT_UNIQUE_CUTOFF)
      @children = Hash.new { |hash, key| hash[key] = Set.new }
      @merged_layers = nil # populated when needed
      @unique_cutoff = unique_cutoff
    end

    # Add a new layer into this set
    # Only add completed layers - otherwise this will collect up incorrect info
    # into the created MergedLayer, since it will "freeze" any current data for
    # total_call_time and similar methods.
    def <<(child)
      metric_type = child.type
      set = children[metric_type]

      if set.size > unique_cutoff
        # find merged_layer
        @merged_layers || init_merged_layers
        @merged_layers[metric_type].absorb(child)
      else
        # we have space just add it
        set << child
      end
    end

    def each
      children.each do |_type, set|
        set.each do |child_layer|
          yield child_layer
        end
      end

      if @merged_layers
        @merged_layers.each do |_type, merged_layer|
          yield merged_layer
        end
      end
    end

    # hold off initializing this until we know we need it
    def init_merged_layers
      @merged_layers = Hash.new { |hash, key| hash[key] = MergedLayer.new(key) }
    end
  end
end
