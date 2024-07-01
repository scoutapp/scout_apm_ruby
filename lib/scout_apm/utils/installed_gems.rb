module ScoutApm
  module Utils
    class InstalledGems
      attr_reader :context

      def initialize(context)
        @context = context
      end

      def logger
        context.logger
      end

      def run
        specs = Bundler.rubygems.public_send(Bundler.rubygems.respond_to?(:installed_specs) ? :installed_specs : :all_specs)
        specs.map { |spec| [spec.name, spec.version.to_s] }
      rescue => e
        logger.warn("Couldn't fetch Gem information: #{e.message}")
        []
      end
    end
  end
end
