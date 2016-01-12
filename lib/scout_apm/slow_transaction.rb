module ScoutApm
  class SlowTransaction
    include ScoutApm::BucketNameSplitter

    BACKTRACE_THRESHOLD = 0.5 # the minimum threshold in seconds to record the backtrace for a metric. decreasing this can have a large impact on overhead/
    BACKTRACE_LIMIT = 5 # Max length of callers to display
    MAX_SIZE = 100 # Limits the size of the metric hash to prevent a metric explosion.

    attr_reader :metric_name
    attr_reader :total_call_time
    attr_reader :metrics
    attr_reader :meta
    attr_reader :uri
    attr_reader :context
    attr_reader :time
    attr_reader :prof
    attr_reader :raw_prof

    # TODO: Move this out of SlowTransaction, it doesn't have much to do w/
    # slow trans other than being a piece of data that ends up in it.
    #
    # Given a call stack, generates a filtered backtrace that:
    # * Limits to the app/models, app/controllers, or app/views directories
    # * Limits to 5 total callers
    # * Makes the app folder the top-level folder used in trace info
    def self.backtrace_parser(backtrace)
      stack = []
      backtrace.each do |c|
        if m=c.match(/(\/app\/(controllers|models|views)\/.+)/)
          stack << m[1]
          break if stack.size == BACKTRACE_LIMIT
        end
      end
      stack
    end

    def initialize(uri, metric_name, total_call_time, metrics, context, time, raw_stackprof)
      @uri = uri
      @metric_name = metric_name
      @total_call_time = total_call_time
      @metrics = metrics
      @context = context
      @time = time
      @prof = ScoutApm::StackprofTreeCollapser.new(raw_stackprof).call
      @raw_prof = raw_stackprof # Send whole data up to server
    end

    # Used to remove metrics when the payload will be too large.
    def clear_metrics!
      @metrics = nil
      self
    end

    def has_metrics?
      metrics and metrics.any?
    end

    def as_json
      json_attributes = [:key, :time, :total_call_time, :uri, [:context, :context_hash], :prof]
      ScoutApm::AttributeArranger.call(self, json_attributes)
    end

    def context_hash
      context.to_hash
    end
  end
end
