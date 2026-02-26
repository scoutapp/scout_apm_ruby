module ScoutApm
  module ServerIntegrations
    class Iodine
      attr_reader :logger

      def initialize(logger)
        @logger = logger
      end

      def name
        :iodine
      end

      def forking?
        false
      end

      def present?
        defined?(::Iodine) && defined?(::Iodine::VERSION)
      end

      def install
      end

      def found?
        true
      end
    end
  end
end
