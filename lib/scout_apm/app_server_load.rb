module ScoutApm
  class AppServerLoad
    attr_reader :logger

    def initialize(logger=Agent.instance.logger)
      @logger = logger
    end

    def run
      @thread = Thread.new do
        begin
          logger.info "Sending Application Startup Info - App Server: #{data[:app_server]}, Framework: #{data[:framework]}, Framework Version: #{data[:framework_version]}, Database Engine: #{data[:database_engine]}"
          logger.debug("Full Application Startup Info: #{data.inspect}")

          payload = ScoutApm::Serializers::AppServerLoadSerializer.serialize(data)
          reporter = Reporter.new(:app_server_load)
          reporter.report(payload)

          logger.debug("Finished sending Startup Info")
        rescue => e
          logger.info("Failed Sending Application Startup Info - #{e.message}")
          logger.debug(e.backtrace.join("\t\n"))
        end
      end
    rescue => e
      logger.debug("Failed Startup Info - #{e.message} \n\t#{e.backtrace.join("\t\n")}")
    end

    def data
      { :server_time        => Time.now,
        :framework          => ScoutApm::Environment.instance.framework_integration.human_name,
        :framework_version  => ScoutApm::Environment.instance.framework_integration.version,
        :environment        => ScoutApm::Environment.instance.framework_integration.env,
        :app_server         => ScoutApm::Environment.instance.app_server,
        :ruby_version       => RUBY_VERSION,
        :hostname           => ScoutApm::Environment.instance.hostname,
        :database_engine    => ScoutApm::Environment.instance.database_engine,      # Detected
        :database_adapter   => ScoutApm::Environment.instance.raw_database_adapter, # Raw
        :application_name   => ScoutApm::Environment.instance.application_name,
        :libraries          => ScoutApm::Utils::InstalledGems.new.run,
        :paas               => ScoutApm::Environment.instance.platform_integration.name,
        :git_revision       => ScoutApm::Environment.instance.git_revision.sha
      }
    end
  end
end
