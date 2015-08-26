module ScoutApm
  module FrameworkIntegrations
    class Rails3Or4
      def name
        :rails3_or_4
      end

      def version
        Rails::VERSION::STRING
      end

      def present?
        defined?(::Rails) &&
          defined?(ActionController) &&
          Rails::VERSION::MAJOR >= 3
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
        ::Rails.env
      end

    end
  end
end
