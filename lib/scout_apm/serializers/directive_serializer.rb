# Serialize & deserialize commands from the APM server to the instrumented app

module ScoutApm
  module Serializers
    class DirectiveSerializer
      def self.serialize(data)
        Marshal.dump(data)
      end

      def self.deserialize(data)
        Marshal.load(data)
      end
    end
  end
end
