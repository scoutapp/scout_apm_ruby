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
    # A hash of { MetricMeta => MetricStat }
    # This holds metrics for specific parts of the application.
    # "Controller/user/index", "ActiveRecord/SQL/users/find", "View/users/_gravatar" and similar.
    #
    # If over the course of a minute a metric is called more than once (very likely), it will be
    # combined with the others of the same type, and summed/calculated.  The merging logic is in
    # MetricStats
    #
    # Use the accessor function `metrics_payload` for most uses. It includes the calculated aggregate values
    attr_reader :metrics

    # An array of SlowTransaction objects
    attr_reader :slow_transactions

    # A StoreReportingPeriodTimestamp representing the time that this
    # collection of metrics is for
    attr_reader :timestamp

    def initialize(timestamp)
      @metrics = Hash.new
      @slow_transactions = Array.new
      @timestamp = timestamp
    end

    #################################
    # Add metrics as they are recorded
    #################################
    def merge_metrics!(metrics)
      @metrics.merge!(metrics) { |key, old_stat, new_stat| old_stat.combine!(new_stat) }
      self
    end

    def merge_slow_transactions!(slow_transactions)
      @slow_transactions += Array(slow_transactions)
      self
    end

    #################################
    # Retrieve Metrics for reporting
    #################################
    def metrics_payload
      aggregate_metrics
    end

    def slow_transactions_payload
      @slow_transactions
    end

    private

    # We can't aggregate CPU, Memory, Capacity, or Controller, so pass through these metrics directly
    # TODO: Figure out a way to not have this duplicate what's in Samplers, and also on server's ingest
    PASSTHROUGH_METRICS = ["CPU", "Memory", "Instance", "Controller"]

    # Calculate any aggregate metrics necessary.
    #
    # A hash of { MetricMeta => MetricStat }
    # This represents the aggregate metrics over the course of the minute.
    # "ActiveRecord/all", "View/all", "HTTP/all" and similar
    def aggregate_metrics
      hsh = Hash.new {|h,k| h[k] = MetricStats.new }

      @metrics.inject(hsh) do |result, (meta, stat)|
        if PASSTHROUGH_METRICS.include?(meta.type) # Leave as-is, don't attempt to combine
          hsh[meta] = stat
        elsif meta.type == "Errors" # Sadly special cased, we want both raw and aggregate values
          hsh[meta] = stat
          agg_meta = MetricMeta.new("Errors/Request", :scope => meta.scope)
          hsh[agg_meta].combine!(stat)
        else # Combine down to a single /all key
          agg_meta = MetricMeta.new("#{meta.type}/all", :scope => meta.scope)
          hsh[agg_meta].combine!(stat)
        end

        hsh
      end
    end
  end
end

