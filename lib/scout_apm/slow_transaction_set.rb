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

    def to_a
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
