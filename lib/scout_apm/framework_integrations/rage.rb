module ScoutApm
  module FrameworkIntegrations
    class Rage
      def name
        :rage
      end

      def human_name
        "Rage"
      end

      def version
        ::Rage::VERSION
      end

      def present?
        defined?(::Rage) && defined?(::Rage::VERSION) && !defined?(::Rails)
      end

      def application_name
        nil
      end

      def env
        ::Rage.env.to_s
      end

      def database_engine
        return @database_engine if @database_engine
        default = :postgres

        @database_engine = if defined?(ActiveRecord::Base)
          adapter = raw_database_adapter

          case adapter.to_s
          when "postgres"   then :postgres
          when "postgresql" then :postgres
          when "postgis"    then :postgres
          when "sqlite3"    then :sqlite
          when "sqlite"     then :sqlite
          when "mysql"      then :mysql
          when "mysql2"     then :mysql
          when "sqlserver"  then :sqlserver
          else default
          end
        else
          default
        end
      end

      def raw_database_adapter
        ActiveRecord::Base.connection_db_config.configuration_hash[:adapter] rescue nil
      end
    end
  end
end
