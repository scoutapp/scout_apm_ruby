# Public API for the Scout Error Monitoring service
#
# See-Also ScoutApm::Transaction and ScoutApm::Tracing for APM related APIs
module ScoutApm
  module Error
    # Capture an exception, optionally with an environment hash. This may be a
    # Rack environment, but is not required.
    class << self
      def capture(exception, env={}, name: "CustomError")
        context = ScoutApm::Agent.instance.context

        # Skip if error monitoring isn't enabled at all
        if ! context.config.value("errors_enabled")
          return false
        end

        exception = validate_or_create_exception(exception, name)
        return false unless exception

        # Skip if this one error is ignored
        if context.ignored_exceptions.ignored?(exception)
          return false
        end

        # Capture the error for further processing and shipping
        context.error_buffer.capture(exception, env)

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
        class_name = name_str.gsub(/(?:^|[_\s])([a-z])/) { $1.upcase }
        Object.const_set(class_name, Class.new(Exception))
      end

      def validate_or_create_exception(exception, name)
        if exception.is_a?(Exception) && exception.backtrace
          exception
        elsif exception.is_a?(Exception)
          exception.tap do |e|
            e.set_backtrace(get_caller_location) # returns Array
          end
        elsif exception.is_a?(String)
          # A name of nil will cause all custom errors to be grouped together under CustomError in the UI.
          define_error_class(name).new(exception).tap do |e|
            e.set_backtrace(get_caller_location)
          end
        else
          ScoutApm::Agent.instance.context.logger.warn "Invalid exception type: #{exception.class}. Expected Exception or String."
          nil
        end
      end
    end
  end
end
