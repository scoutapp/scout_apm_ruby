require 'scout_apm'

module ScoutApm
  module DeployIntegrations
    class Capistrano3
      attr_reader :logger

      def initialize(logger)
        @logger = logger
        @cap = Rake.application rescue nil
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
          defined?(Capistrano::VERSION) && Gem::Dependency.new('', '~> 3.0').match?('', Capistrano::VERSION.to_s)
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
        if reporter.can_report?
          data = deploy_data
          logger.debug "Sending deploy hook data: #{data}"
          payload = ScoutApm::Serializers::DeploySerializer.serialize(data)
          reporter.report(payload, ScoutApm::Serializers::DeploySerializer::HTTP_HEADERS)
        else
          logger.warn "Unable to post deploy hook data"
        end
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