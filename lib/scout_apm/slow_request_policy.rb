# Long running class that determines if, and in how much detail a potentially
# slow transaction should be recorded in

module ScoutApm
  class SlowRequestPolicy
    CAPTURE_TYPES = [
      CAPTURE_DETAIL  = "capture_detail",
      CAPTURE_NONE    = "capture_none",
    ]

    # Adjust speed points. See the function
    POINT_MULTIPLIER_SPEED = 0.25

    # For each minute we haven't seen an endpoint
    POINT_MULTIPLIER_AGE = 0.25

    # Outliers are worth up to "1000ms" of weight
    POINT_MULTIPLIER_PERCENTILE = 1.0

    # Points for an endpoint's who's throughput * response time is a large % of
    # overall time spent processing requests
    POINT_MULTIPLIER_PERCENT_TIME = 2.5

    # A hash of Endpoint Name to the last time we stored a slow transaction for it.
    #
    # Defaults to a start time that is pretty close to application boot time.
    # So the "age" of an endpoint we've never seen is the time the application
    # has been running.
    attr_reader :last_seen

    # The AgentContext we're running in
    attr_reader :context

    def initialize(context)
      @context = context

      zero_time = Time.now
      @last_seen = Hash.new { |h, k| h[k] = zero_time }
    end

    def stored!(request)
      last_seen[request.unique_name] = Time.now
    end

    # Determine if this request trace should be fully analyzed by scoring it
    # across several metrics, and then determining if that's good enough to
    # make it into this minute's payload.
    #
    # Due to the combining nature of the agent & layaway file, there's no
    # guarantee that a high scoring local champion will still be a winner when
    # they go up to "regionals" and are compared against the other processes
    # running on a node.
    def score(request)
      unique_name = request.unique_name
      if unique_name == :unknown
        return -1 # A negative score, should never be good enough to store.
      end

      total_time = request.root_layer.total_call_time

      # How long has it been since we've seen this?
      age = Time.now - last_seen[unique_name]

      # What approximate percentile was this request?
      percentile = context.request_histograms.approximate_quantile_of_value(unique_name, total_time)

      percent_of_total_time = context.transaction_time_consumed.percent_of_total(unique_name)

      return speed_points(total_time) + percentile_points(percentile) + age_points(age) + percent_time_points(percent_of_total_time)
    end

    private

    # Time in seconds
    # Logarithm keeps huge times from swamping the other metrics.
    # 1+ is necessary to keep the log function in positive territory.
    def speed_points(time)
      Math.log(1 + time) * POINT_MULTIPLIER_SPEED
    end

    def percentile_points(percentile)
      if percentile < 40
        0.4 # Don't put much emphasis on capturing low percentiles.
      elsif percentile < 60
        1.4 # Highest here to get mean traces
      elsif percentile < 90
        0.7 # Between 60 & 90% is fine.
      elsif percentile >= 90
        1.4 # Highest here to get 90+%ile traces
      else
        # impossible.
        percentile
      end
    end

    def age_points(age)
      age / 60.0 * POINT_MULTIPLIER_AGE
    end

    # Of the total time spent handling endpoints in this app, if this endpoint
    # is a higher percent, it should get more points.
    #
    # A: 20 calls @ 100ms each => 2 seconds of total time
    # B: 10 calls @ 100ms each => 1 second of total time
    #
    # Then A is 66% of the total call time
    def percent_time_points(percent) # Scale 0.0 - 1.0
      percent * POINT_MULTIPLIER_PERCENT_TIME
    end
  end
end
