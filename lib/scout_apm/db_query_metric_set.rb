module ScoutApm
  class DbQueryMetricSet
    include Enumerable

    attr_reader :metrics # the raw metrics. You probably want #metrics_to_report
    attr_reader :config # A ScoutApm::Config instance

    def initialize(config=ScoutApm::Agent.instance.config)
      # A hash of DbQueryMetricStats values, keyed by DbQueryMetricStats.key
      @metrics = Hash.new
      @config = config
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
      other.each do |metric|
        self << metric
      end
      self
    end

    # Add a single DbQueryMetricStats object to this set.
    #
    # Looks up an existing one under this key and merges, or just saves a new
    # one under the key
    def <<(stat)
      existing_stat = metrics[stat.key]
      if existing_stat
        existing_stat.combine!(stat)
      elsif at_limit?
        # We're full up, can't add any more.
        # Should I log this? It may get super noisy?
      else
        metrics[stat.key] = stat
      end
    end

    def increment_transaction_count!
      metrics.each do |_key, db_query_metric_stat|
        db_query_metric_stat.increment_transaction_count!
      end
    end

    def metrics_to_report
      report_limit = config.value('database_metric_report_limit')
      if metrics.size > report_limit
        metrics.
          values.
          sort_by {|stat| stat.call_time }.
          reverse.
          take(report_limit)
      else
        metrics.values
      end
    end

    def inspect
      metrics.map {|key, metric|
        "#{key.inspect} - Count: #{metric.call_count}, Total Time: #{"%.2f" % metric.call_time}"
      }.join("\n")
    end

    def at_limit?
      @limit ||= config.value('database_metric_limit')
      metrics.size >= @limit
    end
  end
end
