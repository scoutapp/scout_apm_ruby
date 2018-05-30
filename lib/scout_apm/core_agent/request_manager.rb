module ScoutApm
  module CoreAgent
    class RequestManager
      @@instance = nil

      attr_reader :logger
      attr_reader :context

      # All access to the agent is thru this class method to ensure multiple Agent instances are not initialized per-Ruby process.
      def self.instance(options = {})
        @@instance ||= self.new(options)
      end

      def initialize(context)
        @context = context
        @logger = context.logger
        @request_buffer = ScoutApm::CoreAgent::RequestBuffer.new(context)
        @@instance = self
      end

      def add_tracked_request(tracked_request)
        @request_buffer << tracked_request
      end
    end
  end
end