module ScoutApm
  module FrameworkIntegrations
    # on the webmachine github page they say it's not a framework thought
    class Webmachine
      def name
        :webmachine
      end

      def human_name
        "Webmachine"
      end

      def version
        ::Webmachine::VERSION
      end

      def present?
        defined?(::Webmachine) && defined?(::Webmachine::Application)
      end

      def application_name
        File.basename(Dir.getwd)
      rescue => e
        ScoutApm::Agent.instance.context.logger.debug "Failed getting Webmachine Application Name: #{e.message}\n#{e.backtrace.join("\n\t")}"
        "Webmachine"
      end

      def env
        ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
      end

      # TODO: Figure out how to detect this smarter
      def database_engine
        :mysql
      end

      def raw_database_adapter
        :mysql
      end
    end
  end
end
