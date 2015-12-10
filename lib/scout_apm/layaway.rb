# Stores StoreReportingPeriod objects in a file before sending them to the server.
# 1. A centralized store for multiple Agent processes. This way, only 1 checkin is sent to Scout rather than 1 per-process.
module ScoutApm
  class Layaway
    attr_accessor :file

    def initialize
      @file = ScoutApm::LayawayFile.new
    end

    # We're changing the format, so detect if we're loading an old formatted
    # file, and just drop it if so. There's no important data there, since it's
    # used mostly for just syncronizing between processes
    def verify_layaway_file_contents
      file.read_and_write do |existing_data|
        existing_data ||= {}
        if existing_data.keys.all?{|k| k.is_a? StoreReportingPeriodTimestamp } &&
            existing_data.values.all? {|v| v.is_a? StoreReportingPeriod }
          existing_data
        else
          {}
        end
      end
    end

    def add_reporting_period(time, reporting_period)
      file.read_and_write do |existing_data|
        existing_data ||= Hash.new
        existing_data.merge!(time => reporting_period) {|key, old_val, new_val|
          old_val.merge_metrics!(new_val.metrics).merge_slow_transactions!(new_val.slow_transactions)
        }
      end
    end

    REPORTING_INTERVAL = 60 # seconds
    MAX_INTERVALS = 5

    # Returns an array of ReportingPeriod objects that are ready to be pushed to the server
    def periods_ready_for_delivery
      ready_for_delivery = []

      file.read_and_write do |existing_data|
        existing_data ||= {}
        ready_for_delivery = existing_data.select {|time, rp| should_send?(rp) } # Select off the values we want

        # Rewrite anything not plucked out back to the file
        existing_data.reject {|k, v| ready_for_delivery.keys.include?(k) }
      end

      return ready_for_delivery.values
    end

    # We just want to send anything older than X

    def should_send?(reporting_period)
      reporting_period.timestamp.age_in_seconds > REPORTING_INTERVAL
    end
  end
end
