module ScoutApm
  module FrameworkIntegrations
    class Sinatra
      def name
        :sinatra
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
    end
  end
end
