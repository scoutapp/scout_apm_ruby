require 'yaml'
require 'erb'

require 'scout_apm/environment'

# Valid Config Options:
#
# application_root - override the detected directory of the application
# data_file        - override the default temporary storage location. Must be a location in a writable directory
# key              - the account key with Scout APM. Found in Settings in the Web UI
# log_file_path    - either a directory or "STDOUT".
# log_level        - DEBUG / INFO / WARN as usual
# monitor          - true or false.  False prevents any instrumentation from starting
# name             - override the name reported to APM. This is the name that shows in the Web UI
#
# Any of these config settings can be set with an environment variable prefixed
# by SCOUT_ and uppercasing the key: SCOUT_LOG_LEVEL for instance.

module ScoutApm
  class Config
    DEFAULTS =  {
        'host'      => 'https://apm.scoutapp.com',
        'log_level' => 'info',
    }.freeze

    def initialize(config_path = nil)
      @config_path = config_path
    end

    # Fetch a config value.
    # It first attempts to fetch an ENV var prefixed with 'SCOUT_',
    # then from the settings file.
    def value(key)
      value = ENV['SCOUT_'+key.upcase] || setting(key)
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
