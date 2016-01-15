# Stores StoreReportingPeriod objects in a file before sending them to the server.
# 1. A centralized store for multiple Agent processes. This way, only 1 checkin is sent to Scout rather than 1 per-process.
module ScoutApm
  class Layaway
    attr_accessor :file

    def initialize
      @file = ScoutApm::LayawayFile.new
    end

    def add_reporting_period(time, reporting_period)
      file.read_and_write do |existing_data|
        existing_data ||= Hash.new
        existing_data.merge(time => reporting_period) {|key, old_val, new_val|
          old_req = old_val.metrics_payload.
            select { |meta,stats| meta.metric_name =~ /\AController/ }.
            inject(0) {|sum, (_, stat)| sum + stat.call_count }
          new_req = new_val.metrics_payload.
            select { |meta,stats| meta.metric_name =~ /\AController/ }.
            inject(0) {|sum, (_, stat)| sum + stat.call_count }
          ScoutApm::Agent.instance.logger.debug("Merging Two reporting periods (#{old_val.timestamp.to_s}, #{new_val.timestamp.to_s}): old req #{old_req}, new req #{new_req}")

          old_val.merge_metrics!(new_val.metrics_payload).merge_slow_transactions!(new_val.slow_transactions)
        }
      end
    end

    REPORTING_INTERVAL = 60 # seconds

    # Returns an array of ReportingPeriod objects that are ready to be pushed to the server
    def periods_ready_for_delivery
      ready_for_delivery = []
      file.read_and_write do |existing_data|
        existing_data ||= {}
        ready_for_delivery = existing_data.to_a.select {|time, rp| should_send?(rp) } # Select off the values we want. to_a is needed for compatibility with Ruby 1.8.7.

        # Rewrite anything not plucked out back to the file
        existing_data.reject {|k, v| ready_for_delivery.map(&:first).include?(k) }
      end

      return ready_for_delivery.map(&:last)
    end

    # We just want to send anything older than X
    def should_send?(reporting_period)
      reporting_period.timestamp.age_in_seconds > (REPORTING_INTERVAL * 2)
    end
  end
end
