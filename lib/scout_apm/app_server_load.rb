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
      { :server_time        => to_s_safe(Time.now),
        :framework          => to_s_safe(ScoutApm::Environment.instance.framework_integration.human_name),
        :framework_version  => to_s_safe(ScoutApm::Environment.instance.framework_integration.version),
        :environment        => to_s_safe(ScoutApm::Environment.instance.framework_integration.env),
        :app_server         => to_s_safe(ScoutApm::Environment.instance.app_server),
        :ruby_version       => RUBY_VERSION,
        :hostname           => to_s_safe(ScoutApm::Environment.instance.hostname),
        :database_engine    => to_s_safe(ScoutApm::Environment.instance.database_engine),      # Detected
        :database_adapter   => to_s_safe(ScoutApm::Environment.instance.raw_database_adapter), # Raw
        :application_name   => to_s_safe(ScoutApm::Environment.instance.application_name),
        :libraries          => ScoutApm::Utils::InstalledGems.new.run,
        :paas               => to_s_safe(ScoutApm::Environment.instance.platform_integration.name),
        :git_sha            => to_s_safe(ScoutApm::Environment.instance.git_revision.sha)
      }
    end

    # Calls `.to_s` on the object passed in.
    # Returns literal string 'to_s error' if the object does not respond to .to_s
    def to_s_safe(obj)
      if obj.respond_to?(:to_s)
        obj.to_s
      else
        'to_s error'
      end
    end
  end
end
