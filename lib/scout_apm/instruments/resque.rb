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

      # Insert ourselves into the point when resque turns a string "TestJob"
      # into the class constant TestJob, and insert our instrumentation plugin
      # into that constantized class
      #
      # This automates away any need for the user to insert our instrumentation into
      # each of their jobs
      # def inject_job_instrument
      #   ::Resque::Job.class_eval do
      #     def payload_class_with_scout_instruments
      #       klass = payload_class_without_scout_instruments
      #       klass.extend(ScoutApm::Instruments::Resque)
      #       klass
      #     end
      #     alias_method :payload_class_without_scout_instruments, :payload_class
      #     alias_method :payload_class, :payload_class_with_scout_instruments
      #   end
      # end

      # def before_perform_scout_instrument(*args)
      #   ScoutApm::Agent.instance.context.logger.info "resque_debug IN BEFORE PERFORM"
      #   begin
      #     ScoutApm::Agent.instance.context.become_remote_client!(bind, port)
      #     # inject_job_instrument
      #   rescue => e
      #     ScoutApm::Agent.instance.context.logger.warn "Error while Installing Resque before_perform: #{e.inspect}"
      #   end
      # end

      def logger
        ScoutApm::Agent.instance.context.logger
      end

      def around_perform_with_scout_instruments(*args)
        logger.info "resque_debug IN AROUND PERFORM"
        ScoutApm::Agent.instance.context.become_remote_client!(bind, port)
        logger.info "resque_debug REMOTE AGENT"
        job_name = self.to_s
        queue = find_queue

        if job_name == "ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper"
          job_name = args.first["job_class"] rescue job_name
          queue = args.first["queue_name"] rescue queue_name
        end

        logger.info "resque_debug JOB: #{job_name} QUEUE: #{queue}"

        req = ScoutApm::RequestManager.lookup

        # logger.info "resque_debug REQUEST: #{req.inspect}"

        begin
          req.start_layer(ScoutApm::Layer.new('Queue', queue))
          started_queue = true
          req.start_layer(ScoutApm::Layer.new('Job', job_name))
          started_job = true

          logger.info "resque_debug DOING LAYERS"

          yield
        rescue => e
          req.error!
          raise
        ensure
          logger.info "resque_debug ENSURING"
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
