# Contains methods specific to logging (initializing the log file, applying the log level, applying the log format, etc.)
module ScoutApm
  class Agent
    module Logging
      def default_log_path
        "#{environment.root}/log"
      end

      def init_logger(opts={})
        if opts[:force]
          @log_file = nil
          @logger = nil
        end

        begin
          @log_file ||= determine_log_destination
        rescue => e
        end

        begin
          @logger ||= Logger.new(@log_file)
          @logger.level = log_level
          apply_log_format
        rescue Exception => e
          @logger = Logger.new(STDOUT)
          apply_log_format
          @logger.error "Unable to open log file for writing: #{e.message}. Falling back to STDOUT"
        end
        @logger
      end

      def apply_log_format
        def logger.format_message(severity, timestamp, progname, msg)
          # since STDOUT isn't exclusive like the scout_apm.log file, apply a prefix.
          prefix = @logdev.dev == STDOUT ? "[Scout] " : ''
          prefix + "[#{Utils::Time.to_s(timestamp)} #{ScoutApm::Agent.instance.environment.hostname} (#{$$})] #{severity} : #{msg}\n"
        end
      end

      def log_level
        case config.value('log_level').downcase
          when "debug" then Logger::DEBUG
          when "info" then Logger::INFO
          when "warn" then Logger::WARN
          when "error" then Logger::ERROR
          when "fatal" then Logger::FATAL
          else Logger::INFO
        end
      end

      def determine_log_destination
        case true
        when wants_stdout? then STDOUT
        when wants_stderr? then STDERR
        else "#{log_file_path}/scout_apm.log"
        end
      end

      def wants_stdout?
        config.value('log_file_path').to_s.upcase == 'STDOUT' || environment.platform_integration.log_to_stdout?
      end

      def wants_stderr?
        config.value('log_file_path').to_s.upcase == 'STDERR'
      end

      def log_file_path
        config.value('log_file_path') || default_log_path
      end
    end
    include Logging
  end
end

