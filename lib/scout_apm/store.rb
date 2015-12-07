# Stores one or more minute's worth of Metrics/SlowTransactions in local ram.
# When informed to by the background worker, it pushes the in-ram metrics off to
# the layaway file for cross-process aggregation.
module ScoutApm
  class Store
    # A hash of reporting periods. { timestamp => StoreReportingPeriod }
    # where the timestamp is the integer value at the beginning of the minute
    # See #timestamp_for
    attr_reader :reporting_periods

    def initialize
      @reporting_periods = Hash.new { |h,k| h[k] = StoreReportingPeriod.new(k) }
    end

    # A simple way to calculate beginning of the minute
    def timestamp_for(time)
      time.to_i - time.sec
    end

    # What is the timestamp for right now.
    def current_timestamp
      timestamp_for(Time.now)
    end

    # Save newly collected metrics
    def track!(metrics, options={})
      reporting_periods[current_timestamp].merge_metrics!(metrics)
    end

    def track_one!(type, name, value, options={})
      meta = MetricMeta.new("#{type}/#{name}")
      stat = MetricStats.new(false)
      stat.update!(value)
      track!({meta => stat})
    end

    # Save a new slow transaction
    def save_slow_transaction!(slow_transaction)
      reporting_periods[current_timestamp].merge_slow_transactions!(slow_transaction)
    end

    # Take each completed reporting_period, and write it to the layaway passed
    def write_to_layaway(layaway)
      reporting_periods.select { |time, rp| time < current_timestamp }.
                        each { |time, reporting_period|
                               layaway.add_reporting_period(time, reporting_period)
                               reporting_periods.delete(time)
                             }
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

    # Which minute is this StoreReportingPeriod for?
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
      @metrics
      # .merge(aggregate_metrics) # I'm unsure if the agent is responsible for aggregating metrics into a /all attribute?
    end

    def slow_transactions_payload
      @slow_transactions
    end

    private

    # We don't attempt to aggregate some types
    EXCLUDED_AGGREGATES = ["Controller"]

    # Calculate any aggregate metrics necessary.
    #
    # A hash of { MetricMeta => MetricStat }
    # This represents the aggregate metrics over the course of the minute.
    # "ActiveRecord/all", "View/all", "HTTP/all" and similar
    def aggregate_metrics
      hsh = Hash.new {|h,k| h[k] = MetricStats.new }

      @metrics.inject(hsh) do |result, (meta, stat)|
        next if EXCLUDED_AGGREGATES.include?(meta.type)
        agg_meta = MetricMeta.new("#{meta.type}/all")
        hsh[agg_meta].combine!(stat)
        hsh
      end
    end
  end
end

