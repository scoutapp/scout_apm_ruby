# Stores one or more minute's worth of Metrics/SlowTransactions in local ram.
# When informed to by the background worker, it pushes the in-ram metrics off to
# the layaway file for cross-process aggregation.
module ScoutApm
  class Store
    # A hash of reporting periods. { StoreReportingPeriodTimestamp => StoreReportingPeriod }
    attr_reader :reporting_periods

    def initialize
      @mutex = Mutex.new
      @reporting_periods = Hash.new { |h,k| h[k] = StoreReportingPeriod.new(k) }
    end

    def current_timestamp
      StoreReportingPeriodTimestamp.new
    end

    # Save newly collected metrics
    def track!(metrics, options={})
      @mutex.synchronize {
        reporting_periods[current_timestamp].merge_metrics!(metrics)
      }
    end

    def track_one!(type, name, value, options={})
      meta = MetricMeta.new("#{type}/#{name}")
      stat = MetricStats.new(false)
      stat.update!(value)
      track!({meta => stat}, options)
    end

    # Save a new slow transaction
    def track_slow_transaction!(slow_transaction)
      return unless slow_transaction
      @mutex.synchronize {
        reporting_periods[current_timestamp].merge_slow_transactions!(slow_transaction)
      }
    end

    # Take each completed reporting_period, and write it to the layaway passed
    def write_to_layaway(layaway)
      @mutex.synchronize {
        reporting_periods.select { |time, rp| time.timestamp < current_timestamp.timestamp}.
                          each   { |time, rp|
                                   layaway.add_reporting_period(time, rp)
                                   reporting_periods.delete(time)
                                 }
      }
    end
  end

  # A timestamp, normalized to the beginning of a minute. Used as a hash key to
  # bucket metrics into per-minute groups
  class StoreReportingPeriodTimestamp
    attr_reader :timestamp

    def initialize(time=Time.now)
      @raw_time = time.utc # The actual time passed in. Store it so we can to_s it without reparsing a timestamp
      @timestamp = @raw_time.to_i - @raw_time.sec # The normalized time (integer) to compare by
    end

    def to_s
      @raw_time.iso8601
    end

    def eql?(o)
      timestamp.eql?(o.timestamp)
    end

    def hash
      timestamp.hash
    end

    def age_in_seconds
      Time.now.to_i - timestamp
    end
  end

  # One period of Storage. Typically 1 minute
  class StoreReportingPeriod
    # An array of SlowTransaction objects
    attr_reader :slow_transactions

    # A StoreReportingPeriodTimestamp representing the time that this
    # collection of metrics is for
    attr_reader :timestamp

    def initialize(timestamp)
      @timestamp = timestamp

      @slow_transactions = SlowTransactionSet.new
      @aggregate_metrics = Hash.new
    end

    #################################
    # Add metrics as they are recorded
    #################################
    def merge_metrics!(metrics)
      metrics.each { |metric| absorb(metric) }
      self
    end

    def merge_slow_transactions!(slow_transactions)
      @slow_transactions << slow_transaction
      self
    end

    #################################
    # Retrieve Metrics for reporting
    #################################
    def metrics_payload
      @aggregate_metrics
    end

    def slow_transactions_payload
      @slow_transactions.to_a
    end

    private

    # Removes payloads from slow transactions that exceed +SlowRequestPolicy::MAX_DETAIL_PER_MINUTE+ to avoid
    # bloating the layaway file.
    def trim_slow_transaction_metrics
      count_with_metrics = 0
      @slow_transactions.each do |s|

        if s.has_metrics?
          count_with_metrics += 1
          if count_with_metrics > SlowRequestPolicy::MAX_DETAIL_PER_MINUTE
            s.clear_metrics!
          end
        end
      end
    end

    # We can't aggregate CPU, Memory, Capacity, or Controller, so pass through these metrics directly
    # TODO: Figure out a way to not have this duplicate what's in Samplers, and also on server's ingest
    PASSTHROUGH_METRICS = ["CPU", "Memory", "Instance", "Controller"]

    # Absorbs a single new metric into the aggregates
    def absorb(metric)
      meta, stat = metric

      if PASSTHROUGH_METRICS.include?(meta.type) # Leave as-is, don't attempt to combine
        @aggregate_metrics[meta] ||= MetricStats.new
        @aggregate_metrics[meta].combine!(stat)

      elsif meta.type == "Errors" # Sadly special cased, we want both raw and aggregate values
        @aggregate_metrics[meta] ||= MetricStats.new
        @aggregate_metrics[meta].combine!(stat)
        agg_meta = MetricMeta.new("Errors/Request", :scope => meta.scope)
        @aggregate_metrics[agg_meta] ||= MetricStats.new
        @aggregate_metrics[agg_meta].combine!(stat)

      else # Combine down to a single /all key
        agg_meta = MetricMeta.new("#{meta.type}/all", :scope => meta.scope)
        @aggregate_metrics[agg_meta] ||= MetricStats.new
        @aggregate_metrics[agg_meta].combine!(stat)
      end
    end
  end
end

