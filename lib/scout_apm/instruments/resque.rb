module ScoutApm
  module Instruments
    module Resque
      def around_perform_with_scout_instruments(*args)
        job_name = self.to_s
        queue = @queue

        req = ScoutApm::RequestManager.lookup
        req.job!
        # req.annotate_request(:queue_latency => latency(msg))

        begin
          req.start_layer(ScoutApm::Layer.new('Queue', queue))
          started_queue = true
          req.start_layer(ScoutApm::Layer.new('Job', job_name))
          started_job = true

          yield
        rescue => e
          req.error!
          raise
        ensure
          req.stop_layer if started_job
          req.stop_layer if started_queue
        end
      end
    end
  end
end

