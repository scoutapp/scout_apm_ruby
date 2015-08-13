require 'logger'

module ScoutApm
  module Utils
    class NullLogger < Logger
      def initialize(*args)
      end

      def add(*args, &block)
      end
    end
  end
end
