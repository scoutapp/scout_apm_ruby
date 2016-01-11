# In order to keep load down, only record a sample of Slow Transactions.  In
# order to make that sampling as fair as possible, follow a basic algorithm:
#
# When adding a new SlowTransaction:
#  * Just add it if there is an open spot
#  * If there isn't an open spot, attempt to remove an over-represented
#    endpoint instead ("attempt_to_evict"). Overrepresented is simply "has more
#    than @fair number of SlowTransactions for that end point"
#  * If there isn't an open spot, and nobody is valid to evict, drop the
#    incoming SlowTransaction without adding.
#
module ScoutApm
  class SlowTransactionSet
    include Enumerable

    DEFAULT_TOTAL = 10
    DEFAULT_FAIR = 1

    attr_reader :total, :fair

    def initialize(total=DEFAULT_TOTAL, fair=DEFAULT_FAIR)
      @total = total
      @fair = fair
      @slow_transactions = []
    end

    def each
      @slow_transactions.each { |s| yield s }
    end

    def <<(slow_transaction)
      return if attempt_append(slow_transaction)
      attempt_to_evict
      attempt_append(slow_transaction)
    end

    def empty_slot?
      @slow_transactions.length < total
    end

    def attempt_append(slow_transaction)
      if empty_slot?
        @slow_transactions.push(slow_transaction)
        true
      else
        false
      end
    end

    def attempt_to_evict
      return if @slow_transactions.length == 0

      overrepresented = @slow_transactions.
        group_by { |st| st.metric_name }.
        to_a.
        sort_by { |(_, sts)| sts.length }.
        last

      if overrepresented[1].length > fair
        fastest = overrepresented[1].sort_by { |st| st.total_call_time }.first
        @slow_transactions.delete(fastest)
      end
    end
  end
end
