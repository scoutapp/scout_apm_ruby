# Public API for the Scout Error Monitoring service
#
# See-Also ScoutApm::Transaction and ScoutApm::Tracing for APM related APIs
module ScoutApm
  module Error
    # Capture an exception, optionally with an environment hash. This may be a
    # Rack environment, but is not required.
    class ScoutDefined < Exception; end
    class Custom < ScoutDefined; end
      
    class << self
      def capture(exception, context={}, env: {}, name: "ScoutApm::Error::Custom")
        agent_context = ScoutApm::Agent.instance.context

        # Skip if error monitoring isn't enabled at all
        if ! agent_context.config.value("errors_enabled")
          return false
        end

        exception = validate_or_create_exception(exception, name)
        return false unless exception

        # Skip if this one error is ignored
        if agent_context.ignored_exceptions.ignored?(exception)
          return false
        end

        unless env.is_a?(Hash)
          log_warning("Expected env to be a Hash, got #{env.class}")
          env = {}
        end

        unless context.is_a?(Hash)
          log_warning("Expected context to be a Hash, got #{context.class}")
          context = {}
        end
        ScoutApm::Context.add(context)

        # Capture the error for further processing and shipping
        agent_context.error_buffer.capture(exception, env)

        return true
      end

      private

      def get_caller_location
        caller_locations(0, 10)
          .reject { |loc| loc.absolute_path == __FILE__ }
          .map(&:to_s)
      end
      
      def define_error_class(name_str)
        # e.g., "some_error" → "SomeError", "some error" → "SomeError"
        class_name = name_str.gsub(/(?:^|[_\s])([a-zA-Z])/) { $1.upcase }

        if Object.const_defined?(class_name)
          klass = Object.const_get(class_name)
          return klass if klass.ancestors.include?(ScoutApm::Error::ScoutDefined)
          
          log_warning("Error class name '#{class_name}' is already defined. Falling back to ScoutApm::Error::Custom.")
          return Custom
        else
          Object.const_set(class_name, Class.new(ScoutDefined))
        end
      end

      def log_warning(message)
        ScoutApm::Agent.instance.context.logger.warn(message)
      end

      def validate_or_create_exception(exception, name)
        return exception if exception.is_a?(Exception) && exception.backtrace

        if exception.is_a?(Exception)
          exception.tap do |e| 
            e.set_backtrace(get_caller_location)
          end

        elsif exception.is_a?(String)
          define_error_class(name).new(exception).tap do |e|
            e.set_backtrace(get_caller_location)
          end

        else
          log_warning("Invalid exception type: #{exception.class}. Expected Exception or String.")
          nil
        end
      end
    end
  end
end
