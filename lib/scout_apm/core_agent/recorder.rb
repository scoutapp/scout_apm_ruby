require 'securerandom'

# Turns a TrackedRequest into a set of core agent commands, then sends them
module ScoutApm
  module CoreAgent
    class Recorder
      attr_reader :context

      def initialize(context)
        @context = context
      end

      def logger
        context.logger
      end

      def start
        # nothing to do
        self
      end

      def stop
        # nothing to do
      end

      # TODO: Split and extract the data manipulation vs. precondition checking code
      def record!(request)
        return unless preconditions(request)

        batch = BatchCommand.new
        req_id = generate_request_id
        batch << StartRequest.new(req_id, request.root_layer.start_time)

        span_stack = []

        walker = LayerConverters::DepthFirstWalker.new(request.root_layer)
        walker.before do
          span_stack.push(generate_span_id)
        end

        walker.after do
          span_stack.pop
        end

        walker.on do |layer|
          span_id = span_stack[-1] # last is self
          parent = span_stack[-2] # second to last is parent

          batch << StartSpan.new(req_id, span_id, parent, layer.legacy_metric_name, layer.start_time)
          batch << StopSpan.new(req_id, span_id, layer.stop_time)
        end
        walker.walk

        batch << StopRequest.new(req_id, request.root_layer.stop_time)

        ScoutApm::CoreAgent::Socket.instance.send(batch)
      end
    end

    def generate_request_id
      "req-" + SecureRandom.uuid
    end

    def generate_span_id
      "span-" + SecureRandom.uuid
    end

    # Stuff that doesn't belong here. 
    def preconditions(request)
      request.recorded!
      return false if request.ignoring_request?

      # Bail out early if the user asked us to ignore this uri
      return false if @agent_context.ignored_uris.ignore?(request.annotations[:uri])

      request.apply_name_override

      true
    end
  end
end
