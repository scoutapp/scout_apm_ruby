module ScoutApm
  class DbQueryMetricSet
    include Enumerable

    attr_reader :metrics

    def initialize
      # A hash of DbQueryMetricStats values, keyed by DbQueryMetricStats.key
      @metrics = Hash.new
    end

    def each
      metrics.values.each do |db_query_metric_stat|
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
    end

    # Combines two DbQueryMetricStats intances. It's ok to call `combine!` on itself (results in a noop)
    # Returns a DbQueryMetricStats instance
    def <<(stat)
      lookup(stat).combine!(stat)
    end
  end
end
