module ScoutApm
  module ErrorService
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          response = @app.call(env)
        rescue Exception => exception
          puts "[Scout Error Service] Caught Exception: #{exception.class.name}"

          context = ScoutApm::Agent.instance.context

          # Bail out early, and reraise if the error is not interesting.
          if context.ignored_exceptions.ignored?(exception)
            raise
          end

          # Capture the error for further processing and shipping
          context.error_buffer.capture(exception, env)

          # Finally re-raise
          raise
        end

        response
      end
    end
  end
end
