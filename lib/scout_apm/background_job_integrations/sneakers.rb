module ScoutApm
  module BackgroundJobIntegrations
    class Sneakers
      attr_reader :logger

      def name
        :sneakers
      end

      def present?
        defined?(::Sneakers)
      end

      def forking?
        false
      end

      def install
        install_worker_override
      end

      def install_worker_override
        ::Sneakers::Worker.module_eval do
          def initialize_with_scout(*args)
            agent = ::ScoutApm::Agent.instance
            agent.start
            initialize_without_scout(*args)
          end

          alias_method :initialize_without_scout, :initialize
          alias_method :initialize, :initialize_with_scout

          def process_work_with_scout(*args)
            delivery_info, _metadata, msg, _handler = args

            queue = delivery_info[:routing_key] || UNKNOWN_QUEUE_PLACEHOLDER

            job_class = begin
              if self.class == ActiveJob::QueueAdapters::SneakersAdapter::JobWrapper
                msg["job_class"] || UNKNOWN_CLASS_PLACEHOLDER
              else
                self.class.name
              end
            rescue => e
              UNKNOWN_CLASS_PLACEHOLDER
            end

            req = ScoutApm::RequestManager.lookup

            # RabbitMQ does not store a created-at timestamp
            # req.annotate_request(:queue_latency => latency(msg))

            begin
              req.start_layer(ScoutApm::Layer.new('Queue', queue))
              started_queue = true
              req.start_layer(ScoutApm::Layer.new('Job', job_class))
              started_job = true

              process_work_without_scout(*args)
            rescue Exception => e
              req.error!
              raise
            ensure
              req.stop_layer if started_job
              req.stop_layer if started_queue
            end
          end

          alias_method :process_work_without_scout, :process_work
          alias_method :process_work, :process_work_with_scout
        end

        # msg = {
        #   "job_class":"DummyWorker",
        #   "job_id":"ea23ba1c-3022-4e05-870b-c3bcb1c4f328",
        #   "queue_name":"default",
        #   "arguments":["fjdkl"],
        #   "locale":"en"
        # }
      end

      ACTIVE_JOB_KLASS = 'ActiveJob::QueueAdapters::SneakersAdapter::JobWrapper'.freeze
      UNKNOWN_CLASS_PLACEHOLDER = 'UnknownJob'.freeze
      UNKNOWN_QUEUE_PLACEHOLDER = 'default'.freeze
    end
  end
end
