# Attempts to keep the highest score.
#
# Each item must respond to:
#   #call to get the storable item
#   #name to get a unique identifier of the storable
#   #score to get a numeric score, where higher is better
module ScoutApm
  class ScoredItemSet
    include Enumerable

    # A number larger than any score we will actually get.
    ARBITRARILY_LARGE = 100000000

    # Without otherwise saying, default the size to this
    DEFAULT_MAX_SIZE = 10

    # Without otherwise saying, default to enforcing unique endpoints and/or job names.
    DEFAULT_UNIQUE_TRACE_NAMES = true

    attr_reader :max_size
    attr_reader :items

    def initialize(
      unique_trace_names = DEFAULT_UNIQUE_TRACE_NAMES, 
      max_size = DEFAULT_MAX_SIZE
    )
      @items = {}

      # Whether traces should be unique. If set to false, then multiple traces per an endpoint or job can be
      # captured per a reporting period.
      @unique_trace_names = unique_trace_names
  
      @max_size = max_size
    end

    def each
      items.each do |(_, (_, item))|
        yield item
      end
    end

    # This function is a large if statement, with a few branches. See inline comments for each branch.
    def <<(new_item)
      return if new_item.name == :unknown

      # If unique traces name, and we have this item in the hash already, compare the new & old ones
      # and store the new one only if it's higher score.
      if @unique_trace_names && items.has_key?(new_item.name)
        if new_item.score > items[new_item.name].first
          store!(new_item)
        end


      # If the set is full, then we have to see if we evict anything to store
      # this one
      elsif full?
        smallest_name, smallest_score = items.inject([nil, ARBITRARILY_LARGE]) do |(memo_name, memo_score), (name, (stored_score, _))|
          if stored_score < memo_score
            [name, stored_score]
          else
            [memo_name, memo_score]
          end
        end

        if smallest_score < new_item.score
          items.delete(smallest_name)
          store!(new_item)
        end


      # Set isn't full, and we've not seen this new_item (if unique_trace_names), so go ahead and store it.
      else
        store!(new_item)
      end
    end

    # Equal to another set only if exactly the same set of items is inside
    def eql?(other)
      items == other.items
    end

    alias :== :eql?

    private

    def full?
      items.size >= max_size
    end

    def store!(new_item)
      if !new_item.name.nil? # Never store a nil name.

        # The stored name used when evaluting/evicting traces when full.
        realized_stored_name = @unique_trace_names ? new_item.name : "#{new_item.name}-#{new_item.score}"

        items[realized_stored_name] = [new_item.score, new_item.call]
      end
    end

  end
end
