module ScoutApm
  module ErrorService
    class Payload
      def initialize(context, errors)
        @context = context
        @errors = errors
      end

      # TODO: Don't use to_json since it isn't supported in Ruby 1.8.7
      def serialize
        as_json.to_json
      end

      def as_json
        serialized_errors = @errors.map do |error_record|
          serialize_error_record(error_record)
        end

        {
          :problems => serialized_errors,
          :notifier => "scout_apm_ruby",
          :app_environment => context.environment.env,
          :root => context.environment.root,
        }
      end

      def serialize_error_record(error_record)
        {
          :exception_class => error_record.exception_class,
          :message => error_record.message,
          :request_uri => error_record.request_uri,
          :request_params => error_record.request_params,
          :request_session => error_record.request_session,
          :environment => error_record.environment,
          :trace => error_record.trace,
          :request_components => error_record.request_components,
        }
      end
    end
  end
end
