# Serialize & deserialize data from the instrumented app up to the APM server
module ScoutApm
  module Serializers
    class PayloadSerializer
      def self.serialize(metadata, metrics, slow_transactions)
        if ScoutApm::Agent.instance.config.value("report_format") == 'json'
          ScoutApm::Serializers::PayloadSerializerToJson.serialize(metadata, metrics, slow_transactions)
        else
          metadata = metadata.dup
          metadata.default = nil

          metrics = metrics.dup
          metrics.default = nil
          Marshal.dump(:metadata          => metadata,
                       :metrics           => metrics,
                       :slow_transactions => slow_transactions)
        end
      end

      def self.deserialize(data)
        Marshal.load(data)
      end
    end
  end
end
