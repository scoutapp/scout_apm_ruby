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
          adapter = get_database_adapter # can be nil

          case adapter.to_s
          when "postgres"   then :postgres
          when "postgresql" then :postgres
          when "postgis"    then :postgres
          when "sqlite3"    then :sqlite
          when "mysql"      then :mysql
          else default
          end
        else
          # TODO: Figure out how to detect outside of Rails context. (sequel, ROM, etc)
          default
        end
      end

      def get_database_adapter
        ActiveRecord::Base.configurations[env]["adapter"]
      rescue # don't believe this should throw an exception in real-world as only called from #database_engine which checks to see if ActiveRecord::Base is defined.
        nil
      end
    end
  end
end
