module ScoutApm
  class CallSet
    include Enumerable

    N_PLUS_ONE_MAGIC_NUMBER = 5 # Fetch backtraces on this number of calls to a layer. The caller data is only collected on this call (and this + greater) to limit overhead.

    attr_reader :call_count

    def initialize
      @items = []
      @grouped_items = Hash.new { |h, k| h[k] = [] }
      @call_count = 0
      @captured = false
    end

    def each
      @items.each { |s| yield s }
    end

    def update!(item = nil)
      if @captured # No need to do any work if we've already captured a backtrace.
        ScoutApm::Agent.instance.logger.debug "Already captured a backtrace for item [#{item}]"
        return
      end
      @call_count += 1
      if item
        @items << item
        if @grouped_items.any? # lazy grouping as normalizing items can be expensive.
          @grouped_items[unique_name_for(item)] << item
        end
      end
    end

    # We're selective on capturing a backtrace for two reasons:
    # * Grouping ActiveRecord calls requires us to sanitize the SQL. This isn't cheap.
    # * Capturing backtraces isn't cheap.
    # TODO - this doesn't handle a case of some nil items and some non-nil items.
    def capture_backtrace?
      #binding.pry if !@captured && @call_count >= N_PLUS_ONE_MAGIC_NUMBER
      if !@captured && @call_count >= N_PLUS_ONE_MAGIC_NUMBER &&
          ( 
            (!grouping? && @call_count == N_PLUS_ONE_MAGIC_NUMBER ) || # items is empty if the layer doesn't have a description (ex: ActionView). there's no aggregration required here.
            grouped_at_magic_number?
          )
        @captured = true
      end
    end

    def grouping?
      !@items.empty?
    end

    def grouped_at_magic_number?
      res=grouped_items[unique_name_for(@items.last)].size == N_PLUS_ONE_MAGIC_NUMBER
      if res
        ScoutApm::Agent.instance.logger.debug "Grouped Call Set @ magic number."
      end
    end

    def grouped_items
      if @grouped_items.any? 
        @grouped_items
      else
        @grouped_items = @items.group_by { |item| unique_name_for(item) }
      end
    end

    # Determine this items' "hash key"
    def unique_name_for(item)
      item.to_s
    end
  end
end
