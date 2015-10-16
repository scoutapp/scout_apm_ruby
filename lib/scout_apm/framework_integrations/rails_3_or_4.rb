module ScoutApm
  module FrameworkIntegrations
    class Rails3Or4
      def name
        :rails3_or_4
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
          Rails::VERSION::MAJOR >= 3
      end

      def application_name
        if defined?(::Rails)
          ::Rails.application.class.to_s.
             sub(/::Application$/, '')
        end
      rescue
        nil
      end

      def env
        ::Rails.env
      end

      def database_engine
        default = :mysql

        if defined?(ActiveRecord::Base)
          config = ActiveRecord::Base.connection_config
          if config && config[:adapter]
            case config[:adapter].to_s
            when "postgres"   then :postgres
            when "postgresql" then :postgres
            when "postgis"    then :postgres
            when "sqlite3"    then :sqlite
            when "mysql"      then :mysql
            else default
            end
          else
            default
          end
        else
          # TODO: Figure out how to detect outside of Rails context. (sequel, ROM, etc)
          default
        end
      end
    end
  end
end
