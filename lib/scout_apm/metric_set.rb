module ScoutApm
  class MetricSet
    # We can't aggregate CPU, Memory, Capacity, or Controller, so pass through these metrics directly
    # TODO: Figure out a way to not have this duplicate what's in Samplers, and also on server's ingest
    PASSTHROUGH_METRICS = ["CPU", "Memory", "Instance", "Controller", "SlowTransaction"]

    attr_reader :metrics

    def initialize
      @metrics = Hash.new
    end

    def absorb_all(metrics)
      Array(metrics).each { |m| absorb(m) }
    end

    # Absorbs a single new metric into the aggregates
    def absorb(metric)
      meta, stat = metric

      if PASSTHROUGH_METRICS.include?(meta.type) # Leave as-is, don't attempt to combine into an /all key
        @metrics[meta] ||= MetricStats.new
        @metrics[meta].combine!(stat)

      elsif meta.type == "Errors" # Sadly special cased, we want both raw and aggregate values
        @metrics[meta] ||= MetricStats.new
        @metrics[meta].combine!(stat)
        agg_meta = MetricMeta.new("Errors/Request", :scope => meta.scope)
        @metrics[agg_meta] ||= MetricStats.new
        @metrics[agg_meta].combine!(stat)

      else # Combine down to a single /all key
        agg_meta = MetricMeta.new("#{meta.type}/all", :scope => meta.scope)
        @metrics[agg_meta] ||= MetricStats.new
        @metrics[agg_meta].combine!(stat)
      end
    end
  end
end
