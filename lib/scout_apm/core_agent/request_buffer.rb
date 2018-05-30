module ScoutApm
  module CoreAgent
    class RequestBuffer
      attr_reader :logger
      attr_reader :context

      def initialize(context)
        @context = context
        @logger = context.logger
        @requests = []
      end

      def <<(tracked_request)
        @requests << tracked_request
        flush
      end

      def flush
        logger.debug('Flushing Request Buffer')
        flush_request(@requests.unshift) while @requests.any?
      end

      def flush_request(tracked_request)
        batch_command = ScoutApm::CoreAgent::BatchCommand.from_tracked_request(tracked_request)
        ScoutApm::CoreAgent::Socket.instance.send(batch_command)
      end
    end
  end
end