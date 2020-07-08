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

          if ScoutApm::Agent.instance.context.ignored_exceptions.ignore?(exception)
            # Bail out early, and reraise if the error is not interesting.
            raise
          end

          # Extract the data needed
          data = ScoutApm::ErrorService::Data.rack_data(exception, env)

          # Send it for reporting
          ScoutApm::ErrorService::Notifier.notify(data)

          # Finally re-raise
          raise
        end

        response
      end
    end
  end
end
