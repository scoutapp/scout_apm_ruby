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
        if !@cap.nil? && @cap.is_a?(Capistrano::Application)
          require 'capistrano/version'
          return defined?(Capistrano::VERSION) && Gem::Version.new(Capistrano::VERSION).release >= Gem::Version.new('3.0.0')
        else
          return false
        end
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
        payload = ScoutApm::Serializers::PayloadSerializer.serialize_deploy(deploy_data)
        reporter.report(payload, {'Content-Type' => 'application/x-www-form-urlencoded'})
      end

      def reporter
        @reporter ||= ScoutApm::Reporter.new(:deploy_hook, ScoutApm::Agent.instance.config, @logger)
      end

      def deploy_data
        {:revision => current_revision, :branch => branch, :deployed_by => deployed_by}
      end

      def branch
        @cap.fetch(:branch)
      end

      def current_revision
        @cap.fetch(:current_revision) || `git rev-list --max-count=1 --abbrev-commit --abbrev=12 #{branch}`.chomp
      end

      def deployed_by
        ScoutApm::Agent.instance.config.value('deployed_by')
      end

    end
  end
end