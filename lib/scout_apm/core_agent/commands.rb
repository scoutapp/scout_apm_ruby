module ScoutApm
  module CoreAgent
    class RegisterCommand
      def initialize(app, key)
        @app = app
        @key = key
      end

      def message
        {'Register' => {
          'app' => @app,
          'key' => @key,
          'language' => 'ruby',
          'api_version' => '1.0',
        }}
      end
    end

    class BatchCommand
      def initialize(commands=[])
        @commands = commands
      end

      def <<(command)
        @commands << command
      end

      def message
        messages = @commands.map{ |c| c.message }
        {'BatchCommand' => {'commands' => messages}}
      end
    end

    class StartSpan
      def initialize(request_id, span_id, parent, operation, timestamp=Time.now)
        @request_id = request_id
        @span_id = span_id
        @parent = parent
        @operation = operation
        @timestamp = timestamp
      end

      def message
        {'StartSpan': {
          'timestamp': @timestamp.iso8601,
          'request_id': @request_id,
          'span_id': @span_id,
          'parent_id': @parent,
          'operation': @operation,
        }}
      end
    end

    class StopSpan
      def initialize(request_id, span_id, timestamp=Time.now)
        @timestamp = timestamp
        @request_id = request_id
        @span_id = span_id
      end

      def message
        {'StopSpan': {
          'timestamp': @timestamp.iso8601,
          'request_id': @request_id,
          'span_id': @span_id,
        }}
      end
    end


    class StartRequest
      def initialize(request_id, timestamp=Time.now)
        @timestamp = timestamp
        @request_id = request_id
      end

      def message
        {'StartRequest': {
          'timestamp': @timestamp.iso8601,
          'request_id': @request_id,
        }}
      end
    end

    class FinishRequest
      def initialize(request_id, timestamp=Time.now)
        @timestamp = timestamp
        @request_id = request_id
      end

      def message
        {'FinishRequest': {
          'timestamp': @timestamp.iso8601,
          'request_id': @request_id,
        }}
      end
    end


    class TagSpan
      def initialize(request_id, span_id, tag, value, timestamp=Time.now)
        @timestamp = timestamp
        @request_id = request_id
        @span_id = span_id
        @tag = tag
        @value = value
      end

      def message
        {'TagSpan': {
          'timestamp': @timestamp.iso8601,
          'request_id': @request_id,
          'span_id': @span_id,
          'tag': @tag,
          'value': @value,
        }}
      end
    end


    class TagRequest
      def initialize(request_id, tag, value)
        @timestamp = timestamp
        @request_id = request_id
        @tag = tag
        @value = value
      end

      def message
        {'TagRequest': {
          'timestamp': @timestamp.iso8601,
          'request_id': @request_id,
          'tag': @tag,
          'value': @value,
        }}
      end
    end


    class ApplicationEvent
      def initialize(event_type, event_value, source, timestamp=Time.now)
        @event_type = event_type
        @event_value = event_value
        @source = source
        @timestamp = timestamp
      end

      def message
        {'ApplicationEvent': {
          'event_type':  @event_type,
          'event_value': @event_value,
          'timestamp': @timestamp.iso8601,
          'source': @source,
        }}
      end
    end


    class CoreAgentVersion
      def message
        {'CoreAgentVersion': {}}
      end
    end

    class CoreAgentVersionResponse
      def initialize(message)
        parsed = JSON.parse(message)
        version = parsed['CoreAgentVersion']['version']
      end
    end
  end
end
