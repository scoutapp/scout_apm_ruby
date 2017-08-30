module ScoutApm
  class DbQueryMetricSet
    include Enumerable

    attr_reader :metrics

    def initialize
      # A hash of DbQueryMetricStats values, keyed by DbQueryMetricStats.key
      @metrics = Hash.new
    end

    def each
      metrics.each do |_key, db_query_metric_stat|
        yield db_query_metric_stat
      end
    end

    # Looks up a DbQueryMetricStats instance in the +@metrics+ hash. Sets the value to +other+ if no key
    # Returns a DbQueryMetricStats instance
    def lookup(other)
      metrics[other.key] ||= other
    end

    # Take another set, and merge it with this one
    def combine!(other)
      other.metrics.each do |_key, metric|
        self << metric
      end
      self
    end

    # Add a single DbQueryMetricStats object to this set.
    #
    # Looks up an existing one under this key and merges, or just saves a new
    # one under the key
    def <<(stat)
      lookup(stat).combine!(stat)
    end

    def inspect
      metrics.map {|key, metric|
        "#{key.inspect} - Count: #{metric.call_count}, Total Time: #{"%.2f" % metric.call_time}"
      }.join("\n")
    end
  end
end
