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
        request.recorded!
        return false if request.ignoring_request?

        # Bail out early if the user asked us to ignore this uri
        return false if context.ignored_uris.ignore?(request.annotations[:uri])

        request.apply_name_override

        #####

        batch = BatchCommand.new

        ##### Setup the Walker
        # Keeps a stack of span ids (current is last item, parent is second to last)
        req_id = generate_request_id
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

          batch << ScoutApm::CoreAgent::StartSpan.new(req_id, span_id, parent, layer.legacy_metric_name, layer.start_time)

          apply_span_tags(req_id, span_id, layer, batch)

          batch << ScoutApm::CoreAgent::StopSpan.new(req_id, span_id, layer.stop_time)
        end


        #### Actually Run the walker
        batch << ScoutApm::CoreAgent::StartRequest.new(req_id, request.root_layer.start_time)
        apply_request_tags(req_id, request, batch)
        walker.walk
        batch << ScoutApm::CoreAgent::FinishRequest.new(req_id, request.root_layer.stop_time)


        #### Then send the batch over the socket
        context.socket.send(batch)
      end

      def generate_request_id
        "req-" + SecureRandom.uuid
      end

      def generate_span_id
        "span-" + SecureRandom.uuid
      end

      # Request-wide data that should be put in TagRequests
      def apply_request_tags(req_id, request, batch)
        # TODO: Don't lose track of this timestamp
        tag_timestamp = request.root_layer.start_time

        if request.error?
          batch << ScoutApm::CoreAgent::TagRequest.new(req_id, 'error', true, tag_timestamp)
        end

        if request.annotations[:uri]
          batch << ScoutApm::CoreAgent::TagRequest.new(req_id, 'path', request.annotations[:uri], tag_timestamp)
        end

        if request.annotations[:queue_latency]
          batch << ScoutApm::CoreAgent::TagRequest.new(req_id, 'queue_latency', request.annotations[:queue_latency], tag_timestamp)
        end

        request.context.to_flat_hash.each do |key, value|
          batch << ScoutApm::CoreAgent::TagRequest.new(req_id, key, value, tag_timestamp)
        end
      end

      # Per-Span tags
      def apply_span_tags(req_id, span_id, layer, batch)
        # TODO: Don't lose track of this
        tag_timestamp = layer.start_time

        if !layer.backtrace.nil?
          batch << ScoutApm::CoreAgent::TagSpan.new(req_id, span_id, 'stack', layer.backtrace, tag_timestamp)
        end

        if layer.total_allocations > 0
          batch << ScoutApm::CoreAgent::TagSpan.new(req_id, span_id, 'allocations', layer.backtrace, tag_timestamp)
        end

        if layer.desc
          desc_key =
            case layer.type
            when 'ActiveRecord'
              'db.statement'
            else
              'desc'
            end
          batch <<  ScoutApm::CoreAgent::TagSpan.new(req_id, span_id, desc_key, layer.desc, tag_timestamp)
        end

        if layer.annotations && layer.annotations[:record_count]
          batch <<  ScoutApm::CoreAgent::TagSpan.new(req_id, span_id, 'db.record_count', layer.annotations[:record_count], tag_timestamp)
        end
      end
    end
  end
end
