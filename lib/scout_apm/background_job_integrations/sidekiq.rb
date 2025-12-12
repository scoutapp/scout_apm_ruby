module ScoutApm
  module BackgroundJobIntegrations
    class Sidekiq
      attr_reader :logger

      def name
        :sidekiq
      end

      def present?
        defined?(::Sidekiq) && File.basename($PROGRAM_NAME).start_with?('sidekiq')
      end

      def forking?
        false
      end

      def install
        install_tracer
        add_middleware
        install_processor
      end

      def install_tracer
        # ScoutApm::Tracer is not available when this class is defined
        SidekiqMiddleware.class_eval do
          include ScoutApm::Tracer
        end
      end

      def add_middleware
        ::Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add SidekiqMiddleware
          end
        end
      end

      def install_processor
        ::Sidekiq.configure_server do |config|
          config.on(:startup) do
            agent = ::ScoutApm::Agent.instance
            agent.start
          end
        end
      end
    end

    # We insert this middleware into the Sidekiq stack, to capture each job,
    # and time them.
    class SidekiqMiddleware
      def call(_worker, msg, queue)
        req = ScoutApm::RequestManager.lookup
        req.annotate_request(:queue_latency => latency(msg))
        class_name = job_class(msg)

        add_context!(msg, class_name) if capture_job_args?

        begin
          req.start_layer(ScoutApm::Layer.new('Queue', queue))
          started_queue = true
          req.start_layer(ScoutApm::Layer.new('Job', class_name))
          started_job = true

          yield
        rescue
          req.error!
          raise
        ensure
          req.stop_layer if started_job
          req.stop_layer if started_queue
        end
      end

      def self.sidekiq_version_8?
        if defined?(::Sidekiq::VERSION)
          ::Sidekiq::VERSION.to_i >= 8
        else
          false
        end
      end

      UNKNOWN_CLASS_PLACEHOLDER = 'UnknownJob'.freeze
      # This name was changed in Sidekiq 8
      ACTIVE_JOB_KLASS = if sidekiq_version_8?
                          'Sidekiq::ActiveJob::Wrapper'.freeze
                        else
                          'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper'.freeze
                        end
      DELAYED_WRAPPER_KLASS = 'Sidekiq::Extensions::DelayedClass'.freeze


      # Capturing the class name is a little tricky, since we need to handle several cases:
      # 1. ActiveJob, with the class in the key 'wrapped'
      # 2. ActiveJob, but the 'wrapped' key is wrong (due to YAJL serializing weirdly), find it in args.job_class
      # 3. DelayedJob wrapper, deserializing using YAML into the real object, which can be introspected
      # 4. No wrapper, just sidekiq's class
      def job_class(msg)
        job_class = msg.fetch('class', UNKNOWN_CLASS_PLACEHOLDER)

        if job_class == ACTIVE_JOB_KLASS && msg.key?('wrapped') && msg['wrapped'].is_a?(String)
          begin
            job_class = msg['wrapped'].to_s
          rescue
            ACTIVE_JOB_KLASS
          end
        elsif job_class == ACTIVE_JOB_KLASS && msg.try(:[], 'args').try(:[], 'job_class')
          begin
            job_class = msg['args']['job_class'].to_s
          rescue
            ACTIVE_JOB_KLASS
          end
        elsif job_class == DELAYED_WRAPPER_KLASS
          begin
            # Extract the info out of the wrapper
            yml = msg['args'].first
            deserialized_args = YAML.load(yml)
            klass, method, *rest = deserialized_args

            # If this is an instance of a class, get the class itself
            # Prevents instances from coming through named like "#<Foo:0x007ffd7a9dd8a0>"
            klass = klass.class unless klass.is_a? Module

            job_class = [klass, method].map(&:to_s).join(".")
          rescue
            DELAYED_WRAPPER_KLASS
          end
        end

        job_class
      rescue
        UNKNOWN_CLASS_PLACEHOLDER
      end

      def capture_job_args?
        ScoutApm::Agent.instance.context.config.value("job_params_capture")
      end

      def add_context!(msg, class_name)
        return if class_name == UNKNOWN_CLASS_PLACEHOLDER
        
        klass = class_name.constantize rescue nil
        return if klass.nil?

        # Only allow required and optional parameters, as others aren't fully supported by Sidekiq by default.
        # This also keeps it easy in terms of the canonical signature of parameters.
        allowed_parameter_types = [:req, :opt]

        known_parameters =
          klass.instance_method(:perform).parameters.each_with_object([]) do |(type, name), acc|
            acc << name if allowed_parameter_types.include?(type)
          end

        return if known_parameters.empty?

        job_args = if msg["class"] == ACTIVE_JOB_KLASS
            arguments = msg.fetch('args', [])
            # Don't think this can actually happen. With perform_all_later, 
            # it appears we go through this middleware individually (even with multiples of the same job type).
            return if arguments.length > 1

            arguments.first.fetch('arguments', [])
          else
            msg.fetch('args', [])
          end

        # Reduce known parameters to just the ones that are present in the job arguments (excluding non altered optional params)
        known_parameters = known_parameters[0...job_args.length]

        ScoutApm::Context.add(filter_params(known_parameters.zip(job_args).to_h))
      end

      def latency(msg, time = Time.now.to_f)
        created_at = msg['enqueued_at'] || msg['created_at']
        if created_at
          # Sidekiq 8+ uses milliseconds, older versions use seconds.
          # Do it this way because downstream expects seconds.
          if self.class.sidekiq_version_8?
            # Convert milliseconds to seconds for consistency.
            (time - (created_at.to_f / 1000.0))
          else
            (time - created_at)
          end
        else
          0
        end
      rescue
        0
      end

      ###################
      # Filtering Params
      ###################

      # Replaces parameter values with a string / set in config file
      def filter_params(params)
        return params unless filtered_params_config

        params.each do |k, v|
          if filter_key?(k)
            params[k] = "[FILTERED]"
            next
          end

          if filter_value?(v)
            params[k] = "[UNSUPPORTED TYPE]"
          end
        end

        params
      end

      def filter_value?(value)
        !ScoutApm::Context::VALID_TYPES.any? { |klass| value.is_a?(klass) }
      end

      # Check, if a key should be filtered
      def filter_key?(key)
        params_to_filter.any? do |filter|
          key.to_s == filter.to_s # key.to_s.include?(filter.to_s)
        end
      end

      def params_to_filter
        @params_to_filter ||= filtered_params_config + rails_filtered_params
      end

      # TODO: Flip this over to use a new class like filtered exceptions? Some shared logic between
      # this and the error service.
      def filtered_params_config
        ScoutApm::Agent.instance.context.config.value("job_filtered_params")
      end

      def rails_filtered_params
        return [] unless defined?(Rails)
        Rails.configuration.filter_parameters
      rescue 
        []
      end
    end
  end
end
