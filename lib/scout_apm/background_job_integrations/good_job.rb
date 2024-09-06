module ScoutApm
  module BackgroundJobIntegrations
    class GoodJob
      UNKNOWN_QUEUE_PLACEHOLDER = 'default'.freeze
      attr_reader :logger

      def name
        :good_job
      end

      def present?
        defined?(::GoodJob::VERSION)
      end

      def forking?
        false
      end

      def install
        ActiveSupport.on_load(:active_job) do
          include ScoutApm::Tracer

          around_perform do |job, block|
            # I have a sneaking suspicion there is a better way to handle Agent starting
            # Maybe hook into GoodJob lifecycle events?
            req = ScoutApm::RequestManager.lookup
            latency = Time.now - (job.scheduled_at || job.enqueued_at) rescue 0
            req.annotate_request(queue_latency: latency)

            begin
              req.start_layer ScoutApm::Layer.new("Queue", job.queue_name.presence || UNKNOWN_QUEUE_PLACEHOLDER)
              started_queue = true # Following Convention
              req.start_layer ScoutApm::Layer.new("Job", job.class.name)
              started_job = true # Following Convention

              block.call
            rescue
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
  end
end
