module ScoutApm
  module ErrorService
    class Notifier
      attr_reader :context
      attr_reader :reporter

      def initialize(context)
        @context = context
        @reporter = ScoutApm::Reporter.new(context, :errors)
      end

      def ship
        error_records = context.error_buffer.get_and_reset_error_records
        payload = ScoutApm::ErrorService::Payload.new(error_records).serialize
        reporter.report(payload.to_json, extra_headers)
      end

      private

      def extra_headers
        {}
      end
    end
  end
end
