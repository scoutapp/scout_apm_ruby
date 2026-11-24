module ScoutApm
  module Remote
    # Header the forked children send with every message. The value is a token
    # the parent generates before forking, so the children inherit it.
    TOKEN_HEADER = "X-Scout-Remote-Token".freeze

    # Constant-time string comparison, so response timing doesn't reveal how
    # much of the token matched.
    def self.secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      result = 0
      a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
      result == 0
    end

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
      rescue
        ScoutApm::Agent.instance.logger.info("Failed Marshalling Remote::Message")
        ScoutApm::Agent.instance.logger.info(ScoutApm::Utils::MarshalLogging.new(self).dive) rescue nil
        raise
      end
    end
  end
end
