module ScoutApm
  module BackgroundJobIntegrations
    class Resque
      def name
        :resque
      end

      def present?
        defined?(::Resque) &&
          ::Resque.respond_to?(:before_first_fork)
      end

      # Lies. This forks really aggressively, but we have to do handling
      # of it manually here, rather than via any sort of automatic
      # background worker starting
      def forking?
        false
      end

      def install
        install_before_first_fork
        install_instruments
      end

      def install_before_first_fork
        ::Resque.before_first_fork do
          begin
            # Don't check fork_per_job here in case some workers fork_per_job and some don't.
            if ScoutApm::Agent.instance.context.config.value('start_resque_server_instrument')
              ScoutApm::Agent.instance.start
              ScoutApm::Agent.instance.context.start_remote_server!(bind, port)
            else
              logger.info("Not starting remote server due to 'start_resque_server_instrument' setting")
            end
          rescue Errno::EADDRINUSE
            logger.warn "Error while Installing Resque Instruments, Port #{port} already in use. Set via the `remote_agent_port` configuration option"
          rescue => e
            logger.warn "Error while Installing Resque before_first_fork: #{e.inspect}"
          end
        end
      end

      def install_instruments
        ::Resque::Job.class_eval do
          def payload_class_with_scout_instruments
            klass = payload_class_without_scout_instruments
            klass.extend(ScoutApm::Instruments::Resque)
            klass
          end
          alias_method :payload_class_without_scout_instruments, :payload_class
          alias_method :payload_class, :payload_class_with_scout_instruments
        end
      end

      private

      def bind
        config.value("remote_agent_host")
      end

      def port
        config.value("remote_agent_port")
      end

      def config
        @config ||= ScoutApm::Agent.instance.context.config
      end

      def logger
        @logger ||= ScoutApm::Agent.instance.context.logger
      end
    end
  end
end
