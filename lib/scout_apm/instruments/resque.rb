module ScoutApm
  module Instruments
    module Resque
      def bind
        config.value("remote_agent_host")
      end

      def port
        config.value("remote_agent_port")
      end

      def config
        @config || ScoutApm::Agent.instance.context.config
      end

      def logger
        ScoutApm::Agent.instance.context.logger
      end

      def before_perform_become_client(*args)
        ScoutApm::Agent.instance.context.become_remote_client!(bind, port)
        logger.debug "resque_debug REMOTE AGENT"
      end

      def around_perform_with_scout_instruments(*args)
        logger.debug "resque_debug IN AROUND PERFORM"
        job_name = self.to_s
        queue = find_queue

        if job_name == "ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper"
          job_name = args.first["job_class"] rescue job_name
          queue = args.first["queue_name"] rescue queue_name
        end

        logger.debug "resque_debug JOB: #{job_name} QUEUE: #{queue}"

        req = ScoutApm::RequestManager.lookup

        # logger.info "resque_debug REQUEST: #{req.inspect}"

        begin
          req.start_layer(ScoutApm::Layer.new('Queue', queue))
          started_queue = true
          req.start_layer(ScoutApm::Layer.new('Job', job_name))
          started_job = true

          logger.debug "resque_debug DOING LAYERS"

          yield
        rescue => e
          req.error!
          raise
        ensure
          logger.debug "resque_debug ENSURING"
          req.stop_layer if started_job
          req.stop_layer if started_queue
        end
      end

      def find_queue
        return @queue if @queue
        return queue if self.respond_to?(:queue)
        return "unknown"
      end
    end
  end
end
