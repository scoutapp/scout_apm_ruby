# Long running class that determines if, and in how much detail a potentially
# slow transaction should be recorded in
#
# Rules:
#   - Runtime must be slower than a threshold

module ScoutApm
  class SlowRequestPolicy
    CAPTURE_TYPES = [
      CAPTURE_DETAIL  = "capture_detail",
      CAPTURE_NONE    = "capture_none",
    ]

    # Each minute we haven't seen an endpoint makes it "250ms" more weighty
    POINT_MULTIPLIER_AGE = 0.25

    # Outliers are worth up to "1000ms" of weight
    POINT_MULTIPLIER_PERCENTILE = 1

    # Each second is worth "1000ms" of weight
    POINT_MULTIPLIER_SPEED = 1

    # A hash of Endpoint Name to the last time we stored a slow transaction for it.
    #
    # Defaults to a start time that is pretty close to application boot time.
    # So the "age" of an endpoint we've never seen is the time the application
    # has been running.
    attr_reader :last_seen

    DEFAULT_HISTOGRAM_SIZE = 50

    # A hash of Endpoint Name to an approximate histogram
    #
    # Each time a new request is requested to see if it's slow or not, we
    # should insert it into the histogram, and get the approximate percentile
    # of that time
    attr_reader :histograms

    def initialize(histogram_size = DEFAULT_HISTOGRAM_SIZE)
      zero_time = Time.now

      @last_seen = Hash.new { |h, k| h[k] = zero_time }
      @histograms = Hash.new { |h, k| h[k] = NumericHistogram.new(histogram_size) }
    end

    def stored!(metric_name)
      last_seen[metric_name] = Time.now
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
      unique_name = unique_name_for(request)
      if unique_name == :unknown
        return -1 # A negative score, should never be good enough to store.
      end

      total_time = request.root_layer.total_call_time

      # How long has it been since we've seen this?
      age = Time.now - last_seen[unique_name]

      # Always store off histogram time
      histogram = histograms[unique_name]
      histogram.add(total_time)
      percentile = histogram.approximate_quantile_of_value(total_time)

      points = speed_points(total_time) + percentile_points(percentile) + age_points(age)

      points
    end

    private

    def unique_name_for(request)
      scope_layer = LayerConverters::ConverterBase.new(request).scope_layer
      if scope_layer
        scope_layer.legacy_metric_name
      else
        :unknown
      end
    end

    # Time in seconds
    def speed_points(time)
      time * POINT_MULTIPLIER_SPEED
    end

    def percentile_points(percentile)
      percentile * POINT_MULTIPLIER_PERCENTILE
    end

    def age_points(age)
      age * POINT_MULTIPLIER_AGE
    end
  end
end
