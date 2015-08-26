module ScoutApm
  module FrameworkIntegrations
    class Rails2
      def name
        :rails
      end

      def human_name
        "Rails"
      end

      def version
        Rails::VERSION::STRING
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
