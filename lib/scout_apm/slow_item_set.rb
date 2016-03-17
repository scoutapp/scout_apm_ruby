# In order to keep load down, only record a sample of Slow Items (Transactions
# or Jobs).  In order to make that sampling as fair as possible, follow a basic
# algorithm:
#
# When adding a new Slow Item:
#  * Just add it if there is an open spot
#  * If there isn't an open spot, attempt to remove an over-represented
#    item instead ("attempt_to_evict"). Overrepresented is simply "has more
#    than @fair number of Matching Items in the set"
#  * If there isn't an open spot, and no Item is valid to evict, drop the
#    incoming Item without adding.
#
# There is no way to remove Items from this set, create a new object
# for each reporting period.

module ScoutApm
  class SlowItemSet
    include Enumerable

    DEFAULT_TOTAL = 10
    DEFAULT_FAIR = 1

    attr_reader :total
    attr_reader :fair

    def initialize(total=DEFAULT_TOTAL, fair=DEFAULT_FAIR)
      @total = total
      @fair = fair
      @items = []
    end

    def each
      @items.each { |s| yield s }
    end

    def <<(item)
      return if attempt_append(item)
      attempt_to_evict
      attempt_append(item)
    end

    def empty_slot?
      @items.length < total
    end

    def attempt_append(item)
      if empty_slot?
        @items.push(item)
        true
      else
        false
      end
    end

    def attempt_to_evict
      return if @items.length == 0

      overrepresented = @items.
        group_by { |item| unique_name_for(item) }.
        to_a.
        sort_by { |(_, items)| items.length }.
        last

      if overrepresented[1].length > fair
        fastest = overrepresented[1].sort_by { |item| item.total_call_time }.first
        @items.delete(fastest)
      end
    end

    # Determine this items' "hash key"
    def unique_name_for(item)
      item.metric_name
    end
  end
end
