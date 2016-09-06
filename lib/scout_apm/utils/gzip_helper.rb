module ScoutApm
  module Utils
    # A simple wrapper around Ruby's built-in gzip support.
    class GzipHelper
      DEFAULT_GZIP_LEVEL = 5

      attr_reader :level

      def initialize(level = DEFAULT_GZIP_LEVEL)
        @level = level
      end

      def deflate(str)
        Zlib::Deflate.deflate(str, level)
      end
    end
  end
end
