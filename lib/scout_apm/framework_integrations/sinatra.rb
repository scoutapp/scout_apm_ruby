module ScoutApm
  module FrameworkIntegrations
    class Sinatra
      def name
        :sinatra
      end

      def human_name
        "Sinatra"
      end

      def version
        Sinatra::VERSION
      end

      def present?
        defined?(::Sinatra) &&
          defined?(::Sinatra::Base)
      end

      # TODO: Fetch the name
      def application_name
        "Sinatra"
      end

      def env
        ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
      end

      # TODO: Figure out how to detect this smarter
      def database_engine
        :mysql
      end
    end
  end
end
