module ScoutApm
  module BackgroundJobIntegrations
    class DelayedJob
      attr_reader :logger

      def name
        :delayed_job
      end

      def present?
        defined?(::Delayed::Job) && File.basename($PROGRAM_NAME).start_with?('delayed_job')
      end

      def forking?
        false
      end

      def install
        plugin = Class.new(Delayed::Plugin) do
          require 'delayed_job'

          callbacks do |lifecycle|
            lifecycle.around(:invoke_job) do |job, *args, &block|
              name = job.name
              queue = job.queue || "default"

              req = ScoutApm::RequestManager.lookup
              req.job!
              # req.annotate_request(:queue_latency => latency(msg))

              queue_layer = ScoutApm::Layer.new('Queue', queue)
              job_layer = ScoutApm::Layer.new('Job', name)

              ScoutApm::Agent.instance.logger.debug("Starting DelayedJob #{queue}/#{name}")

              begin
                req.start_layer(queue_layer)
                started_queue = true
                req.start_layer(job_layer)
                started_job = true

                # Call the job itself.
                block.call(job, *args)

                ScoutApm::Agent.instance.logger.debug("Finished DelayedJob #{queue}/#{name}")
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

        Delayed::Worker.plugins << plugin # ScoutApm::BackgroundJobIntegrations::DelayedJobPlugin
      end
    end
  end
end

