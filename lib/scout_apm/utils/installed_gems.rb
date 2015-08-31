module ScoutApm
  module Utils
    class InstalledGems
      attr_reader :logger

      def initialize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
      end

      def run
        Bundler.rubygems.all_specs.map {|spec| [spec.name, spec.version.to_s] }
      rescue => e
        logger.warn("Couldn't fetch Gem information: #{e.message}")
        []
      end
    end
  end
end
