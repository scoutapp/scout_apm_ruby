# Serialize & deserialize deploy data up to the APM server
module ScoutApm
  module Serializers
    class DeploySerializer
      HTTP_HEADERS = {'Content-Type' => 'application/x-www-form-urlencoded'}

      def self.serialize(data)
        URI.encode_www_form(data)
      end

      def self.deserialize(data)
        Marshal.load(data)
      end
    end
  end
end
