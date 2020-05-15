module ScoutApm
  module ErrorService
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          response = @app.call(env)
        rescue Exception => exception
          puts "[Scout Error Service] Caught Exception: #{exception.class.name}"

          data = ScoutApm::ErrorService::Data.rack_data(exception, env)
          ScoutApm::ErrorService::Notifier.notify(data)

          raise
        end

        response
      end
    end
  end
end
