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

    def initialize(histogram_size = DEFAULT_HISTOGRAM_SIZE)
      initialize_histograms_hash
    end

    def each_name
      @histograms.keys.each { |n| yield n }
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
      initialize_histograms_hash
    end

    def initialize_histograms_hash
      @histograms = Hash.new { |h, k| h[k] = NumericHistogram.new(histogram_size) }
    end
  end
end
