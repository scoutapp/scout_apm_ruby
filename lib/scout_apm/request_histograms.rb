module ScoutApm
  class RequestHistograms
    DEFAULT_HISTOGRAM_SIZE = 50

    # Private Accessor:
    # A hash of Endpoint Name to an approximate histogram
    #
    # Each time a new request is requested to see if it's slow or not, we
    # should insert it into the histogram, and get the approximate percentile
    # of that time
    attr_reader :histograms
    private :histograms

    attr_reader :histogram_size

    def initialize(histogram_size = DEFAULT_HISTOGRAM_SIZE)
      @mutex = Monitor.new
      @histogram_size = histogram_size
      initialize_histograms_hash
    end

    def each_name
      @mutex.synchronize do
        @histograms.keys.each { |n| yield n }
      end
    end

    def as_json
      @mutex.synchronize do
        Hash[
          @histograms.map{ |key, histogram|
            [key, histogram.as_json]
          }
        ]
      end
    end

    def add(item, value)
      @histograms[item].add(value)
    end

    def approximate_quantile_of_value(item, value)
      @histograms[item].approximate_quantile_of_value(value)
    end

    def quantile(item, q)
      @histograms[item].quantile(q)
    end

    # Wipes all histograms, setting them back to empty
    def reset_all!
      @mutex.synchronize do
        initialize_histograms_hash
      end
    end

    def raw(item)
      @histograms[item]
    end

    def initialize_histograms_hash
      @mutex.synchronize do
        @histograms = Hash.new { |h, k| h[k] = NumericHistogram.new(histogram_size) }
      end
    end
  end
end
