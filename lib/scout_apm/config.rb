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
# report_format    - 'json' or 'marshal'. Marshal is legacy and will be removed.
#
# Any of these config settings can be set with an environment variable prefixed
# by SCOUT_ and uppercasing the key: SCOUT_LOG_LEVEL for instance.


# Config - Made up of config overlay
# Default -> File -> Environment Var
# QUESTION: How to embed arrays or hashes into ENV?

module ScoutApm
  class Config
    # Load up a config instance without attempting to load a file.
    # Useful for bootstrapping.
    def self.without_file
      overlays = [
        ConfigEnvironment.new,
        ConfigDefaults.new,
      ]
      new(overlays)
    end

    # Load up a config instance, attempting to load a yaml file.  Allows a
    # definite location if requested, or will attempt to load the default
    # configuration file: APP_ROOT/config/scout_apm.yml
    def self.with_file(file_path=nil)
      overlays = [
        ConfigEnvironment.new,
        ConfigFile.new(file_path),
        ConfigDefaults.new,
      ]
      new(overlays)
    end

    def initialize(overlays)
      @overlays = overlays
    end

    def value(key)
      @overlays.each do |overlay|
        if result = overlay.value(key)
          return result
        end
      end

      nil
    end

    class ConfigDefaults
      DEFAULTS = {
        'host'                   => 'https://checkin.scoutapp.com',
        'direct_host'            => 'https://apm.scoutapp.com',
        'log_level'              => 'info',
        'uri_reporting'          => 'full_path',
        'report_format'          => 'json',
        'disabled_instruments'   => [],
        'enable_background_jobs' => true,
        'ignore_traces' => [],
      }.freeze

      def value(key)
        DEFAULTS[key]
      end
    end

    class ConfigEnvironment
      def value(key)
        val = ENV['SCOUT_' + key.upcase]
        val.to_s.strip.length.zero? ? nil : val
      end
    end

    # Attempts to load a configuration file, and parse it as YAML. If the file
    # is not found, inaccessbile, or unparsable, log a message to that effect,
    # and move on.
    class ConfigFile
      def initialize(file_path=nil)
        @resolved_file_path = file_path || determine_file_path
        load_file(@resolved_file_path)
      end

      def value(key)
        if @file_loaded
          val = @settings[key]
          val.to_s.strip.length.zero? ? nil : val
        else
          nil
        end
      end

      private

      def load_file(file)
        if !File.exist?(@resolved_file_path)
          logger.info("Configuration file #{file} does not exist, skipping.")
          @file_loaded = false
          return
        end

        if !app_environment
          logger.info("Could not determine application environment, aborting configuration file load")
          @file_loaded = false
          return
        end

        begin
          raw_file = File.read(@resolved_file_path)
          erb_file = ERB.new(raw_file).result(binding)
          parsed_yaml = YAML.load(erb_file)
          @settings = parsed_yaml[app_environment]

          if !@settings.is_a? Hash
            raise ("Missing environment key for: #{app_environment}. This can happen if the key is missing, or with a malformed configuration file," +
                   " check that there is a top level #{app_environment} key.")
          end

          logger.info("Loaded Configuration: #{@resolved_file_path}. Using environment: #{app_environment}")
          @file_loaded = true
        rescue Exception => e # Explicit `Exception` handling to catch SyntaxError and anything else that ERB or YAML may throw
          logger.info("Failed loading configuration file: #{e.message}. ScoutAPM will continue starting with configuration from ENV and defaults")
          @file_loaded = false
        end
      end

      def determine_file_path
        File.join(ScoutApm::Environment.instance.root, "config", "scout_apm.yml")
      end

      def app_environment
        ScoutApm::Environment.instance.env
      end

      # TODO: Make this better
      def logger
        ScoutApm::Agent.instance.logger || Logger.new(STDOUT)
      end
    end
  end
end
