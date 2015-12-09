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
          old = instance_method(:initialize)
          define_method(:initialize) do |boss|
            ScoutApm::Agent.instance.start_background_worker
            old.bind(self).call(boss)
          end
        end
      end
    end

    class SidekiqMiddleware
      def call(worker, msg, queue)
        msg_args = msg["args"].first
        job_class = msg_args["job_class"]
        scout_method_name = "Job/#{job_class}"
        latency = (Time.now.to_f - (msg['enqueued_at'] || msg['created_at'])) * 1000

        self.class.track!("Queue/#{queue}",0,{:extra_metrics => {:latency => latency}})
        self.class.scout_apm_trace(scout_method_name, {:extra_metrics => {:queue => queue}}) do
          yield
        end
      end
    end
  end
end
