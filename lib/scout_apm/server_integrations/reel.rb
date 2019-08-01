module ScoutApm
  module ServerIntegrations
    class Reel
      attr_reader :logger

      def initialize(logger)
        @logger = logger
      end

      def name
        :reel
      end

      def forking?; false; end

      def present?
        defined?(::Reel) && defined?(::Reel::VERSION)
      end

      # TODO: What does it mean to install on a non-forking env?
      def install
      end

      def found?
        true
      end
    end
  end
end


