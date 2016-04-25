# Create one of these at startup time, and ask it if a certain worker's
# processing time is slow enough for us to collect a slow trace.
#
# Keeps track of a histogram of times for each worker class (spearately), and
# uses a percentile of normal to mark individual runs as "slow".
#
# This assumes that all worker calls will be requested once to `slow?`, so that
# the data can be stored
module ScoutApm
  class SlowJobPolicy
    DEFAULT_HISTOGRAM_SIZE = 50

    QUANTILE = 95

    def initialize(histogram_size = DEFAULT_HISTOGRAM_SIZE)
      @histograms = Hash.new { |h, k| h[k] = NumericHistogram.new(histogram_size) }
    end

    # worker: just the worker class name. "PasswordResetJob" or similar
    # total_time: runtime of the job in seconds
    # returns true if this request should be stored in higher trace detail, false otherwise
    def slow?(worker, total_time)
      @histograms[worker].add(total_time)
      return false if @histograms[worker].total == 1 # First call is never slow

      total_time >= @histograms[worker].quantile(QUANTILE)
    end
  end
end
