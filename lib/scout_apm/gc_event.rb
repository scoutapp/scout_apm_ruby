module ScoutApm
  class GcEvent
    def initialize(gc_data)
      @gc_data = gc_data
    end

    def valid?
      (@gc_data[:start_gc_count] > 0) && (@gc_data[:start_gc_count] == @gc_data[:end_gc_count])
    end

    def rss_increased?
      rss_size_diff > 0
    end

    def rss_decreased?
      rss_size_diff < 0
    end

    def rss_size_diff
      @gc_data[:end_max_rss] - @gc_data[:start_max_rss]
    end
  end
end
