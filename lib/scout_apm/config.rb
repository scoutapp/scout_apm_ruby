require 'yaml'
require 'erb'

require 'scout_apm/environment'

# Valid Config Options:
#
# This list is complete, but some are old and unused, or for developers of
# scout_apm itself. See the documentation at http://help.apm.scoutapp.com for
# customer-focused documentation.
#
# application_root - override the detected directory of the application
# compress_payload - true/false to enable gzipping of payload
# data_file        - override the default temporary storage location. Must be a location in a writable directory
# dev_trace        - true or false. Enables always-on tracing in development environmen only
# direct_host      - override the default "direct" host. The direct_host bypasses the ingestion pipeline and goes directly to the webserver, and is primarily used for features under development.
# enable_background_jobs - true or false
# host             - configuration used in development
# hostname         - override the default hostname detection. Default varies by environment - either system hostname, or PAAS hostname
# key              - the account key with Scout APM. Found in Settings in the Web UI
# log_file_path    - either a directory or "STDOUT".
# log_level        - DEBUG / INFO / WARN as usual
# monitor          - true or false.  False prevents any instrumentation from starting
# name             - override the name reported to APM. This is the name that shows in the Web UI
# profile          - turn on/off scoutprof (only applicable in Gem versions including scoutprof)
# proxy            - an http proxy
# report_format    - 'json' or 'marshal'. Marshal is legacy and will be removed.
# scm_subdirectory - if the app root lives in source management in a subdirectory. E.g. #{SCM_ROOT}/src
# uri_reporting    - 'path' or 'full_path' default is 'full_path', which reports URL params as well as the path.
# remote_agent_host - Internal: What host to bind to, and also send messages to for remote. Default: 127.0.0.1.
# remote_agent_port - What port to bind the remote webserver to
#
# Any of these config settings can be set with an environment variable prefixed
# by SCOUT_ and uppercasing the key: SCOUT_LOG_LEVEL for instance.

module ScoutApm
  class Config
    KNOWN_CONFIG_OPTIONS = [
        'application_root',
        'async_recording',
        'compress_payload',
        'config_file',
        'data_file',
        'database_metric_limit',
        'database_metric_report_limit',
        'detailed_middleware',
        'dev_trace',
        'direct_host',
        'disabled_instruments',
        'enable_background_jobs',
        'host',
        'hostname',
        'ignore',
        'key',
        'log_class',
        'log_file_path',
        'log_level',
        'log_stderr',
        'log_stdout',
        'monitor',
        'name',
        'profile',
        'proxy',
        'remote_agent_host',
        'remote_agent_port',
        'report_format',
        'scm_subdirectory',
        'uri_reporting',
        'instrument_http_url_length',
        'core_agent_dir',
        'core_agent_download',
        'core_agent_launch',
        'core_agent_version',
        'download_url',
        'socket_path',
    ]

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

    class IntegerCoercion
      def coerce(val)
        val.to_i
      end
    end

    # Simply returns the passed in value, without change
    class NullCoercion
      def coerce(val)
        val
      end
    end


    SETTING_COERCIONS = {
      "async_recording"        => BooleanCoercion.new,
      "detailed_middleware"    => BooleanCoercion.new,
      "dev_trace"              => BooleanCoercion.new,
      "enable_background_jobs" => BooleanCoercion.new,
      "ignore"                 => JsonCoercion.new,
      "monitor"                => BooleanCoercion.new,
      'database_metric_limit'  => IntegerCoercion.new,
      'database_metric_report_limit' => IntegerCoercion.new,
      'instrument_http_url_length' => IntegerCoercion.new,
    }


    ################################################################################
    # Configuration layers & reading
    ################################################################################

    # Load up a config instance without attempting to load a file.
    # Useful for bootstrapping.
    def self.without_file(context)
      overlays = [
        ConfigEnvironment.new,
        ConfigDefaults.new,
        ConfigNull.new,
      ]
      new(context, overlays)
    end

    # Load up a config instance, attempting to load a yaml file.  Allows a
    # definite location if requested, or will attempt to load the default
    # configuration file: APP_ROOT/config/scout_apm.yml
    def self.with_file(context, file_path=nil, config={})
      overlays = [
        ConfigEnvironment.new,
        ConfigFile.new(context, file_path, config),
        ConfigDefaults.new,
        ConfigNull.new,
      ]
      new(context, overlays)
    end

    def initialize(context, overlays)
      @context = context
      @overlays = Array(overlays)
    end

    # For a given key, what is the first overlay says that it can handle it?
    def overlay_for_key(key)
      @overlays.detect{ |overlay| overlay.has_key?(key) }
    end

    def value(key)
      if ! KNOWN_CONFIG_OPTIONS.include?(key)
        logger.debug("Requested looking up a unknown configuration key: #{key} (not a problem. Evaluate and add to config.rb)")
      end

      o = overlay_for_key(key)
      raw_value = if o
                    o.value(key)
                  else
                    # No overlay said it could handle this key, bail out with nil.
                    nil
                  end

      coercion = SETTING_COERCIONS.fetch(key, NullCoercion.new)
      coercion.coerce(raw_value)
    end

    # Did we load anything for configuration?
    def any_keys_found?
      @overlays.any? { |overlay| overlay.any_keys_found? }
    end

    # Returns an array of config keys, values, and source
    # {key: "monitor", value: "true", source: "environment"}
    #
    def all_settings
      KNOWN_CONFIG_OPTIONS.inject([]) do |memo, key|
        o = overlay_for_key(key)
        memo << {:key => key, :value => value(key).inspect, :source => o.name}
      end
    end

    def log_settings(logger)
      logger.debug(
        "Resolved Setting Values:\n" +
        all_settings.map{|hsh| "#{hsh[:source]} - #{hsh[:key]}: #{hsh[:value]}"}.join("\n")
      )
    end

    def logger
      @context.logger
    end

    class ConfigDefaults
      DEFAULTS = {
        'compress_payload'       => true,
        'detailed_middleware'    => false,
        'dev_trace'              => false,
        'direct_host'            => 'https://apm.scoutapp.com',
        'disabled_instruments'   => [],
        'enable_background_jobs' => true,
        'host'                   => 'https://checkin.scoutapp.com',
        'ignore'                 => [],
        'log_level'              => 'info',
        'profile'                => true, # for scoutprof
        'report_format'          => 'json',
        'scm_subdirectory'       => '',
        'uri_reporting'          => 'full_path',
        'remote_agent_host'      => '127.0.0.1',
        'remote_agent_port'      => 7721, # picked at random
        'database_metric_limit'  => 5000, # The hard limit on db metrics
        'database_metric_report_limit' => 1000,
        'instrument_http_url_length' => 300,
        'core_agent_dir'         => '/tmp/scout_apm_core',
        'core_agent_download'    => true,
        'core_agent_launch'      => true,
        'core_agent_version'     => 'latest',
        'download_url'           => 'https://s3-us-west-1.amazonaws.com/scout-public-downloads/apm_core_agent/release',

        # Core Agent TODO: Fix the reference to `latest` here.
        'socket_path'            => "/tmp/scout_apm_core/scout_apm_core-latest-#{ScoutApm::Environment.instance.arch}-#{ScoutApm::Environment.instance.core_agent_platform}/core-agent.sock"
      }.freeze

      def value(key)
        DEFAULTS[key]
      end

      def has_key?(key)
        DEFAULTS.has_key?(key)
      end

      # Defaults are here, but not counted as user specified.
      def any_keys_found?
        false
      end

      def name
        "defaults"
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

      def any_keys_found?
        false
      end

      def name
        "no-config"
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

      def any_keys_found?
        KNOWN_CONFIG_OPTIONS.any? { |option|
          ENV.has_key?(key_to_env_key(option))
        }
      end

      def name
        "environment"
      end
    end

    # Attempts to load a configuration file, and parse it as YAML. If the file
    # is not found, inaccessbile, or unparsable, log a message to that effect,
    # and move on.
    class ConfigFile
      def initialize(context, file_path=nil, config={})
        @context = context
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

      def any_keys_found?
        KNOWN_CONFIG_OPTIONS.any? { |option|
          @settings.has_key?(option)
        }
      end

      def name
        "config-file"
      end

      private

      attr_reader :context

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
          file_settings = parsed_yaml[app_environment]

          if file_settings.is_a? Hash
            logger.debug("Loaded Configuration: #{@resolved_file_path}. Using environment: #{app_environment}")
            @settings = file_settings
            @file_loaded = true
          else
            logger.info("Couldn't find configuration in #{@resolved_file_path} for environment: #{app_environment}. Configuration in ENV will still be applied.")
            @file_loaded = false
          end
        rescue Exception => e # Explicit `Exception` handling to catch SyntaxError and anything else that ERB or YAML may throw
          logger.info("Failed loading configuration file (#{@resolved_file_path}): #{e.message}. ScoutAPM will continue starting with configuration from ENV and defaults")
          @file_loaded = false
        end
      end

      def determine_file_path
        File.join(context.environment.root, "config", "scout_apm.yml")
      end

      def app_environment
        @config[:environment] || context.environment.env
      end

      def logger
        context.logger
      end
    end
  end
end
