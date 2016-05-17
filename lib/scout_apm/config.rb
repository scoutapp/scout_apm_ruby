require 'yaml'
require 'erb'

require 'scout_apm/environment'

# Valid Config Options:
#
# application_root - override the detected directory of the application
# data_file        - override the default temporary storage location. Must be a location in a writable directory
# host             - override the default hostname detection. Default varies by environment - either system hostname, or PAAS hostname
# direct_host      - override the default "direct" host. The direct_host bypasses the ingestion pipeline and goes directly to the webserver, and is primarily used for features under development.
# key              - the account key with Scout APM. Found in Settings in the Web UI
# log_file_path    - either a directory or "STDOUT".
# log_level        - DEBUG / INFO / WARN as usual
# monitor          - true or false.  False prevents any instrumentation from starting
# name             - override the name reported to APM. This is the name that shows in the Web UI
# uri_reporting    - 'path' or 'full_path' default is 'full_path', which reports URL params as well as the path.
# report_format    - 'json' or 'marshal'. Marshal is currently the default; json processing is in beta
#
# Any of these config settings can be set with an environment variable prefixed
# by SCOUT_ and uppercasing the key: SCOUT_LOG_LEVEL for instance.

module ScoutApm
  class Config
    DEFAULTS =  {
        'host'      => 'https://checkin.scoutapp.com',
        'direct_host' => 'https://apm.scoutapp.com',
        'log_level' => 'info',
        'stackprof_interval' => 20000, # microseconds, 1000 = 1 millisecond, so 20k == 20 milliseconds
        'uri_reporting' => 'full_path',
        'report_format' => 'json',
        'disabled_instruments' => [],
        'enable_background_jobs' => true,
        'ignore_traces' => [],
    }.freeze

    def initialize(config_path = nil)
      @config_path = config_path
    end

    def config_file_exists?
      File.exist?(config_path)
    end

    # Fetch a config value.
    # It first attempts to fetch an ENV var prefixed with 'SCOUT_',
    # then from the settings file.
    #
    # If you set env_only, then it will not attempt to read the config file at
    # all, and only read off the ENV var this is useful to break a loop during
    # boot, where we needed an option to set the application root.
    def value(key, env_only=false)
      value = if env_only
                ENV['SCOUT_' + key.upcase]
              else
                ENV['SCOUT_' + key.upcase] || setting(key)
              end

      value.to_s.strip.length.zero? ? nil : value
    end

    private

    def config_path
      @config_path || File.join(ScoutApm::Environment.instance.root, "config", "scout_apm.yml")
    end

    def config_file
      File.expand_path(config_path)
    end

    def setting(key)
      settings[key] || settings(true)[key]
    end

    def settings(try_reload=false)
      (@settings.nil? || try_reload) ? @settings = load_file : @settings
    end

    def config_environment
      @config_environment ||= ScoutApm::Environment.instance.env
    end

    def load_file
      settings_hash = {}
      begin
        if File.exist?(config_file)
          settings_hash = YAML.load(ERB.new(File.read(config_file)).result(binding))[config_environment] || {}
        else
          logger.warn "No config file found at [#{config_file}]."
        end
      rescue Exception => e
        logger.warn "Unable to load the config file."
        logger.warn e.message
        logger.warn e.backtrace
      end
      DEFAULTS.merge(settings_hash)
    end

    # if we error out early enough, we don't have access to ScoutApm's logger
    # in that case, be silent unless ENV['SCOUT_DEBUG'] is set, then STDOUT it
    def logger
      if defined?(ScoutApm::Agent) && (apm_log = ScoutApm::Agent.instance.logger)
        apm_log
      else
        require 'scout_apm/utils/null_logger'
        ENV['SCOUT_DEBUG'] ? Logger.new(STDOUT) : ScoutApm::Utils::NullLogger.new
      end
    end
  end
end
