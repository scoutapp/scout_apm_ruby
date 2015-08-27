# Methods related to sending metrics to scoutapp.com.
module ScoutApm
  class Agent
    module Reporting
      def reporter
        @reporter ||= ScoutApm::Reporter.new(config, logger)
      end

      # Called in the worker thread. Merges in-memory metrics w/those on disk and reports metrics
      # to the server.
      def process_metrics
        logger.debug "Processing metrics"
        run_samplers
        capacity.process
        payload = layaway.deposit_and_deliver

        metrics = payload[:metrics]
        slow_transactions = payload[:slow_transactions]

        if payload.any?
          add_metric_ids(metrics)

          logger.warn "Some data may be lost - metric size is at limit" if metrics.size == ScoutApm::Store::MAX_SIZE
          # for debugging, count the total number of requests
          controller_count = 0

          metrics.each do |meta,stats|
            if meta.metric_name =~ /\AController/
              controller_count += stats.call_count
            end
          end

          logger.debug("Metrics: #{metrics}")
          logger.debug("SlowTrans: #{slow_transactions}")

          payload = ScoutApm::Serializers::PayloadSerializer.serialize(metrics, slow_transactions)
          slow_transactions_kb = Marshal.dump(slow_transactions).size/1024 # just for performance debugging
          logger.debug "#{config.value('name')} Delivering total payload [#{payload.size/1024} KB] for #{controller_count} requests and slow transactions [#{slow_transactions_kb} KB] for #{slow_transactions.size} transactions of durations: #{slow_transactions.map(&:total_call_time).join(',')}."

          response = reporter.report(payload)

          if response and response.is_a?(Net::HTTPSuccess)
            directives = ScoutApm::Serializers::DirectiveSerializer.deserialize(response.body)

            self.metric_lookup.merge!(directives[:metric_lookup])
            if directives[:reset]
              logger.info "Resetting metric_lookup."
              self.metric_lookup = Hash.new
            end
            logger.debug "Metric Cache Size: #{metric_lookup.size}"
          elsif response
            logger.warn "Error on checkin to #{reporter.uri.to_s}: #{response.inspect}"
          end
        end
      rescue
        logger.warn "Error on checkin to #{reporter.uri.to_s}"
        logger.info $!.message
        logger.debug $!.backtrace
      end

      # Before reporting, lookup metric_id for each MetricMeta. This speeds up
      # reporting on the server-side.
      def add_metric_ids(metrics)
        metrics.each do |meta,stats|
          if metric_id = metric_lookup[meta]
            meta.metric_id = metric_id
          end
        end
      end

      # Called from #process_metrics, which is run via the background worker.
      def run_samplers
        @samplers.each do |sampler|
          begin
            result = sampler.run
            store.track!(sampler.metric_name, result, {:scope => nil}) if result
          rescue => e
            logger.info "Error reading #{sampler.human_name}"
            logger.debug e.message
            logger.debug e.backtrace.join("\n")
          end
        end
      end
    end # module Reporting
    include Reporting
  end # class Agent
end # module ScoutApm
