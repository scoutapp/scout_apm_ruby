# Holds onto exceptions, and moves them forward to shipping when appropriate
module ScoutApm
  module ErrorService
    class ErrorBuffer
      include Enumerable

      def initialize(agent_context)
        @context = agent_context
        @error_records = []
      end

      def capture(exception, env)
        @error_records << ErrorRecord.new(exception, env)
      end

      def each
        @error_records.each do |error_record|
          yield error_record
        end
      end

      def ship
        @error_records.each do |error_record|
          data = ScoutApm::ErrorService::Data.rack_data(error_record.exception, error_record.env)
          ScoutApm::ErrorService::Notifier.notify(data)
        end
      end

      private

      ErrorRecord = Struct.new(:exception, :env)
    end
  end
end
