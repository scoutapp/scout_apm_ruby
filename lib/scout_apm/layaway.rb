# Stores metrics in a file before sending them to the server. Two uses:
# 1. A centralized store for multiple Agent processes. This way, only 1 checkin is sent to Scout rather than 1 per-process.
# 2. Bundling up reports from multiple timeslices to make updates more efficent server-side.
#
# Data is stored in a Hash, where the keys are Time.to_i on the minute. The value is a Hash {:metrics => Hash, :slow_transactions => Array}.
# When depositing data, the new data is either merged with an existing time or placed in a new key.
module ScoutApm
  class Layaway
    attr_accessor :file

    def initialize
      @file = ScoutApm::LayawayFile.new
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

    # Returns an array of ReportingPeriod objects that are ready to be pushed to the server
    def periods_ready_for_delivery
      ready_for_delivery = []

      file.read_and_write do |existing_data|
        existing_data ||= {}
        # Existing Data is:
        # {
        #   time(now-1m) => reporting period,
        #   time(now-2m) => reporting period,
        #   time(now-3m) => reporting period,
        # }

        # And I want the -2m, and -1m
        ready_for_delivery = existing_data.select {|time, _| time < Store.new.current_timestamp - REPORTING_INTERVAL }

        # Rewrite anything not plucked out.
        existing_data.reject {|k, v| ready_for_delivery.keys.include?(k) }
      end

      return ready_for_delivery.values
    end
  end
end
