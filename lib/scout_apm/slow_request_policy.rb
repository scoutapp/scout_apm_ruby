# Long running class that determines if, and in how much detail a potentially
# slow transaction should be recorded in
#
# Rules:
#   - Runtime must be slower than a threshold

module ScoutApm
  class SlowRequestPolicy
    CAPTURE_TYPES = [
      CAPTURE_DETAIL  = "capture_detail",
      CAPTURE_COUNT   = "capture_count",
      CAPTURE_NONE    = "capture_none",
    ]

    # It's not slow unless it's at least this slow
    SLOW_REQUEST_TIME_THRESHOLD = 2.0 # seconds

    # Don't attempt to store more that this in memory
    SLOW_REQUEST_COUNT_THRESHOLD = 5

    def capture_type(time)
      if !slow_enough?(time)
        CAPTURE_NONE
      elsif ScoutApm::Agent.instance.store.current_period.slow_transactions.size <= SLOW_REQUEST_COUNT_THRESHOLD
        CAPTURE_DETAIL
      else
        CAPTURE_COUNT
      end
    end

    private

    def slow_enough?(time)
      time > SLOW_REQUEST_TIME_THRESHOLD
    end
  end
end
