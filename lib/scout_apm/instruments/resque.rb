module ScoutApm
  module Instruments
    module Resque
      def before_perform_become_client(*args)
        # Don't become remote client if explicitly disabled or if forking is disabled to force synchronous recording.
        if config.value('start_resque_server_instrument') && forking?
          ScoutApm::Agent.instance.context.become_remote_client!(bind, port)
        else
          logger.debug("Not becoming remote client due to 'start_resque_server_instrument' setting or 'fork_per_job' setting")
        end
      end

      def around_perform_with_scout_instruments(*args)
        job_name = self.to_s
        queue = find_queue

        if job_name == "ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper"
          job_name = args.first["job_class"] rescue job_name
          queue = args.first["queue_name"] rescue queue_name
        end

        req = ScoutApm::RequestManager.lookup

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

      def find_queue
        return @queue if @queue
        return queue if self.respond_to?(:queue)
        return "unknown"
      end

      private

      def bind
        config.value("remote_agent_host")
      end

      def port
        config.value("remote_agent_port")
      end

      def config
        @config ||= ScoutApm::Agent.instance.context.config
      end

      def logger
        @logger ||= ScoutApm::Agent.instance.context.logger
      end

      def forking?
        @forking ||= ENV["FORK_PER_JOB"] != "false"
      end
    end
  end
end
