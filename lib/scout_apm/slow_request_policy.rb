# Long running class that determines if, and in how much detail a potentially
# slow transaction should be recorded in
#
# Rules:
#   - Runtime must be slower than a threshold

module ScoutApm
  class SlowRequestPolicy
    CAPTURE_TYPES = [
      CAPTURE_DETAIL  = "capture_detail",
      CAPTURE_SUMMARY = "capture_summary",
      CAPTURE_NONE    = "capture_none",
    ]

    # It's not slow unless it's at least this slow
    SLOW_REQUEST_TIME_THRESHOLD = 2.0 # seconds

    def capture_type(time)
      return CAPTURE_NONE unless slow_enough?(time)
      return CAPTURE_DETAIL
    end

    private

    def slow_enough?(time)
      time > SLOW_REQUEST_TIME_THRESHOLD
    end
  end
end
