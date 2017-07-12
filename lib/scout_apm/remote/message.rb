module ScoutApm
  module Remote
    class Message
      attr_reader :type
      attr_reader :command
      attr_reader :args

      def initialize(type, command, *args)
        @type = type
        @command = command
        @args = args
      end

      def self.decode(msg)
        Marshal.load(msg)
      end

      def encode
        Marshal.dump(self)
      end
    end
  end
end
