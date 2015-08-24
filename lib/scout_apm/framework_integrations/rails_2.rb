module ScoutApm
  module FrameworkIntegrations
    class Rails2
      def name
        :rails
      end

      def present?
        defined?(::Rails) &&
          defined?(ActionController) &&
          Rails::VERSION::MAJOR < 3
      end

      def application_name
        if defined?(::Rails)
          ::Rails.application.class.to_s
            .sub(/::Application$/, '')
        end
      rescue
        nil
      end

      def env
        RAILS_ENV.dup
      end
    end
  end
end
