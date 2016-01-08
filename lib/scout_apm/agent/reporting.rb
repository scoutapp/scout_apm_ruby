# Methods related to sending metrics to scoutapp.com.
module ScoutApm
  class Agent
    module Reporting
      def reporter
        @reporter ||= ScoutApm::Reporter.new(:checkin, config, logger)
      end

      # The data moves through a treadmill of reporting, coordinating several Rails processes by using an external file.
      # * During the minute it is being recorded by the instruments, it gets
      #   recorded into the ram of each process (in the Store class).
      # * The minute after, each process writes its own metrics to a shared LayawayFile
      # * The minute after that, the first process to wake up pushes the combined
      #   data to the server, and wipes it. Next processes don't have anything to do.
      #
      # At any given point, there is data in each of those steps, moving its way through the process
      def process_metrics
        # First we write the previous minute's data to the shared-across-process layaway file.
        store.write_to_layaway(layaway)

        # Then attempt to send 2 minutes ago's data up to the server.  This
        # only acctually occurs if this process is the first to wake up this
        # minute.
        report_to_server
      end

      MAX_AGE_TO_REPORT = (10 * 60) # ten minutes as seconds

      # In a running app, one process will get one period ready for delivery, the others will see 0.
      def report_to_server
        reporting_periods = layaway.periods_ready_for_delivery
        reporting_periods.reject! {|rp| rp.timestamp.age_in_seconds > MAX_AGE_TO_REPORT }
        reporting_periods.each do |rp|
          deliver_period(rp)
        end
      end

      def deliver_period(reporting_period)
        metrics = reporting_period.metrics_payload
        slow_transactions = reporting_period.slow_transactions_payload
        metadata = {
          :app_root      => ScoutApm::Environment.instance.root.to_s,
          :unique_id     => ScoutApm::Utils::UniqueId.simple,
          :agent_version => ScoutApm::VERSION,
          :agent_time    => reporting_period.timestamp.to_s,
          :agent_pid     => Process.pid,
          :platform      => "ruby",
        }

        log_deliver(metrics, slow_transactions, metadata)

        payload = ScoutApm::Serializers::PayloadSerializer.serialize(metadata, metrics, slow_transactions)
        response = reporter.report(payload, headers)
        unless response && response.is_a?(Net::HTTPSuccess)
          logger.warn "Error on checkin to #{reporter.uri.to_s}: #{response.inspect}"
        end
      rescue => e
        logger.warn "Error on checkin to #{reporter.uri.to_s}"
        logger.info e.message
        logger.debug e.backtrace
      end

      def log_deliver(metrics, slow_transactions, metadata)
        total_request_count = metrics.
          select { |meta,stats| meta.metric_name =~ /\AController/ }.
          inject(0) {|sum, (_, stat)| sum + stat.call_count }

        memory_stat = metrics.
          find {|meta,stats| meta.metric_name =~ /\AMemory/ }.
          last
        process_log_str = if memory_stat
                            "Recorded from #{memory_stat.call_count} processes"
                          else
                            "Recorded across (unknown) processes"
                          end


        logger.info "Delivering #{metrics.length} Metrics for #{total_request_count} requests and #{slow_transactions.length} Slow Transaction Traces, #{process_log_str}"
        logger.debug("Metrics: #{metrics.pretty_inspect}\nSlowTrans: #{slow_transactions.pretty_inspect}\nMetadata: #{metadata.inspect.pretty_inspect}")
      end

      # TODO: Move this into PayloadSerializer?
      def headers
        if ScoutApm::Agent.instance.config.value("report_format") == 'json'
          headers = {'Content-Type' => 'application/json'}
        else
          headers = {}
        end
      end

      # def process_metrics
      # rescue
        # logger.warn "Error on checkin to #{reporter.uri.to_s}"
        # logger.info $!.message
        # logger.debug $!.backtrace
      # end

      # Before reporting, lookup metric_id for each MetricMeta. This speeds up
      # reporting on the server-side.
      def add_metric_ids(metrics)
        metrics.each do |meta,stats|
          if metric_id = metric_lookup[meta]
            meta.metric_id = metric_id
          end
        end
      end
    end
    include Reporting
  end
end
