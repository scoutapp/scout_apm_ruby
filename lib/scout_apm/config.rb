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
# dev_trace        - true or false. Enables always-on tracing in development environmen only
# enable_background_jobs - true or false
#
# Any of these config settings can be set with an environment variable prefixed
# by SCOUT_ and uppercasing the key: SCOUT_LOG_LEVEL for instance.


# Config - Made up of config overlay
# Default -> File -> Environment Var
# QUESTION: How to embed arrays or hashes into ENV?

module ScoutApm
  class Config

    ################################################################################
    # Coersions
    #
    # Since we get values from environment variables, which are always strings,
    # we need to be able to coerce them into the correct data type.  For
    # instance, setting "SCOUT_ENABLE=false" should be interpreted as being the
    # boolean false, not a string that is present & true.
    #
    # Similarly, this will help parsing YAML configurations if the user has a
    # key like:
    #   monitor: "false"
    ################################################################################

    # Any boolean is passed through
    # A string is false iff it is 0 length, is "f", or "false" - otherwise true
    # An number is false if it is exactly 0
    # Other types are false
    class BooleanCoercion
      def coerce(val)
        case val
        when NilClass
          false
        when TrueClass
          val
        when FalseClass
          val
        when String
          coerce_string(val)
        when Numeric
          val != 0
        else
          false
        end
      end

      def coerce_string(val)
        val = val.downcase.strip
        return false if val.length == 0
        return false if val == "f"
        return false if val == "false"

        true
      end
    end

    # If the passed value is a string, attempt to decode as json
    # This is a no-op unless the `JSON` constant is defined
    class JsonCoercion
      def coerce(val)
        case val
        when String
          if defined?(JSON) && JSON.respond_to?(:parse)
            JSON.parse(val)
          else
            val
          end
        else
          val
        end
      end
    end

    # Simply returns the passed in value, without change
    class NullCoercion
      def coerce(val)
        val
      end
    end


    SETTING_COERCIONS = {
      "monitor"                => BooleanCoercion.new,
      "enable_background_jobs" => BooleanCoercion.new,
      "dev_trace"              => BooleanCoercion.new,
      "ignore"                 => JsonCoercion.new,
    }


    ################################################################################
    # Configuration layers & reading
    ################################################################################

    # Load up a config instance without attempting to load a file.
    # Useful for bootstrapping.
    def self.without_file
      overlays = [
        ConfigEnvironment.new,
        ConfigDefaults.new,
        ConfigNull.new,
      ]
      new(overlays)
    end

    # Load up a config instance, attempting to load a yaml file.  Allows a
    # definite location if requested, or will attempt to load the default
    # configuration file: APP_ROOT/config/scout_apm.yml
    def self.with_file(file_path=nil, config={})
      overlays = [
        ConfigEnvironment.new,
        ConfigFile.new(file_path, config[:file]),
        ConfigDefaults.new,
        ConfigNull.new,
      ]
      new(overlays)
    end

    def initialize(overlays)
      @overlays = Array(overlays)
    end

    def value(key)
      o = @overlays.detect{ |overlay| overlay.has_key?(key) }
      raw_value = if o
                    o.value(key)
                  else
                    # No overlay said it could handle this key, bail out with nil.
                    nil
                  end

      coercion = SETTING_COERCIONS[key] || NullCoercion.new
      coercion.coerce(raw_value)
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
        'ignore'                 => [],
        'dev_trace' => false, # false for now so code can live in main branch
      }.freeze

      def value(key)
        DEFAULTS[key]
      end

      def has_key?(key)
        DEFAULTS.has_key?(key)
      end
    end


    # Good News: It has every config value you could want
    # Bad News: The content of that config value is always nil
    # Used for the null-object pattern
    class ConfigNull
      def value(*)
        nil
      end

      def has_key?(*)
        true
      end
    end

    class ConfigEnvironment
      def value(key)
        val = ENV[key_to_env_key(key)]
        val.to_s.strip.length.zero? ? nil : val
      end

      def has_key?(key)
        ENV.has_key?(key_to_env_key(key))
      end

      def key_to_env_key(key)
        'SCOUT_' + key.upcase
      end
    end

    # Attempts to load a configuration file, and parse it as YAML. If the file
    # is not found, inaccessbile, or unparsable, log a message to that effect,
    # and move on.
    class ConfigFile
      def initialize(file_path=nil, config={})
        @config = config || {}
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

      def has_key?(key)
        @settings.has_key?(key)
      end

      private

      def load_file(file)
        @settings = {}
        if !File.exist?(@resolved_file_path)
          logger.debug("Configuration file #{file} does not exist, skipping.")
          @file_loaded = false
          return
        end

        if !app_environment
          logger.debug("Could not determine application environment, aborting configuration file load")
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

          logger.debug("Loaded Configuration: #{@resolved_file_path}. Using environment: #{app_environment}")
          @file_loaded = true
        rescue Exception => e # Explicit `Exception` handling to catch SyntaxError and anything else that ERB or YAML may throw
          logger.debug("Failed loading configuration file: #{e.message}. ScoutAPM will continue starting with configuration from ENV and defaults")
          @file_loaded = false
        end
      end

      def determine_file_path
        File.join(ScoutApm::Environment.instance.root, "config", "scout_apm.yml")
      end

      def app_environment
        @config[:environment] || ScoutApm::Environment.instance.env
      end

      def logger
        if ScoutApm::Agent.instance.logger
          return ScoutApm::Agent.instance.logger
        else
          l = Logger.new(STDOUT)
          if ENV["SCOUT_LOG_LEVEL"] == "debug"
            l.level = Logger::DEBUG
          else
            l.level = Logger::INFO
          end

          return l
        end
      end
    end
  end
end
