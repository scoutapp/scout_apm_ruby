module ScoutApm
  module BackgroundJobIntegrations
    class Sidekiq
      attr_reader :logger

      def name
        :sidekiq
      end

      def present?
        defined?(::Sidekiq) && (File.basename($0) =~ /\Asidekiq/)
      end

      def forking?
        false
      end

      def install
        # ScoutApm::Tracer is not available when this class is defined
        SidekiqMiddleware.class_eval do
          include ScoutApm::Tracer
        end

        ::Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add SidekiqMiddleware
          end
        end

        require 'sidekiq/processor' # sidekiq v4 has not loaded this file by this point

        ::Sidekiq::Processor.class_eval do
          def initialize_with_scout(boss)
            ::ScoutApm::Agent.instance.start_background_worker unless ::ScoutApm::Agent.instance.background_worker_running?
            initialize_without_scout(boss)
          end

          alias_method :initialize_without_scout, :initialize
          alias_method :initialize, :initialize_with_scout
        end
      end
    end

    class SidekiqMiddleware
      def call(worker, msg, queue)
        job_class = msg["class"] # TODO: Validate this across different versions of Sidekiq
        if job_class == "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper" && msg.has_key?("wrapped")
          job_class = msg["wrapped"]
        end

        latency = (Time.now.to_f - (msg['enqueued_at'] || msg['created_at']))

        req = ScoutApm::RequestManager.lookup
        req.job!
        req.annotate_request(:queue_latency => latency)

        queue_layer = ScoutApm::Layer.new("Queue", queue)
        job_layer = ScoutApm::Layer.new("Job", job_class)

        # Capture ScoutProf if we can
        req.enable_profiled_thread!
        job_layer.set_root_class(job_class)
        job_layer.traced!

        req.start_layer(queue_layer)
        req.start_layer(job_layer)

        begin
          yield
        rescue
          req.error!
          raise
        end
      ensure
        req.stop_layer # Job
        req.stop_layer # Queue
      end
    end
  end
end
