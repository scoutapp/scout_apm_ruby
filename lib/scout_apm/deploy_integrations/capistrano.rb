require 'scout_apm'

module ScoutApm
  module DeployIntegrations
    class Capistrano3
      attr_reader :logger

      def initialize(logger)
        @logger = logger
        @cap = Rake.application
      end

      def name
        :capistrano_3
      end

      def version
        present? ? Capistrano::VERSION : nil
      end

      def present?
        require 'capistrano/version'
        return defined?(Capistrano::VERSION) && Gem::Version.new(Capistrano::VERSION).release >= Gem::Version.new('3.0.0')
      rescue
        return false
      end

      def install
        logger.debug "Initializing Capistrano3 Deploy Integration."
        load File.expand_path("../capistrano_3.cap", __FILE__)
      end

      def root
        '.'
      end

      def env
        @cap.fetch(:stage).to_s
      end

      def found?
        true
      end

      def report
        reporter.report(nil)
      end

      def reporter
        @reporter ||= ScoutApm::Reporter.new(:deploy_hook, ScoutApm::Agent.instance.config, @logger)
      end
    end
  end
end