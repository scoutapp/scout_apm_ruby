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
        true
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
        msg_args = msg["args"].first
        job_class = msg_args["job_class"]
        latency = (Time.now.to_f - (msg['enqueued_at'] || msg['created_at'])) * 1000

        req = ScoutApm::RequestManager.lookup

        req.start_layer( ScoutApm::Layer.new("Queue", queue) )

        ScoutApm::Agent.instance.store.track_one!("Queue", "Latency", latency)

        req.start_layer( ScoutApm::Layer.new("Job", job_class) )

        begin
          yield
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end
    end
  end
end
