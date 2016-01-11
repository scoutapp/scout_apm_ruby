# Long running class that provides a yes/no answer to see if a transaction counts as a "slow transaction"
#
# Rules:
#   - Runtime must be slower than a threshold
#   - Log detailed metrics only for the first X
#   - Stop logging anything after a maximum

module ScoutApm
  class SlowRequestPolicy
    CAPTURE_TYPES = [
      CAPTURE_DETAIL  = "capture_detail",
      CAPTURE_SUMMARY = "capture_summary",
      CAPTURE_NONE    = "capture_none",
    ]

    # It's not slow unless it's at least this slow
    SLOW_REQUEST_TIME_THRESHOLD = 2.0 # seconds

    # Stop recording detailed metrics after this count.  Still record the fact
    # a slow request happened though
    MAX_DETAIL_PER_MINUTE = 10

    # Stop recording anything after this number of slow transactions in a
    # minute.  Will also log a message once per minute that it is stopping
    # recording.
    MAX_PER_MINUTE = 500

    def initialize
      @minute_count = 0
      @detailed_count = 0 # How many detailed slow transactions have we captured this minute?
      @minute = Time.now.min
      @clipped_recording = false
    end

    def capture_type(time)
      reset_counters

      return CAPTURE_NONE unless slow_enough?(time)
      return CAPTURE_NONE if clip_recording?

      @minute_count += 1

      if @detailed_count < MAX_DETAIL_PER_MINUTE
        @detailed_count += 1
        return CAPTURE_DETAIL
      else
        return CAPTURE_SUMMARY
      end
    end

    private

    def reset_counters
      t = Time.now.min
      return if t == @minute

      @minute_count = 0
      @detailed_count = 0
      @minute = t
      @clipped_recording = false
    end

    def slow_enough?(time)
      time > SLOW_REQUEST_TIME_THRESHOLD
    end

    # Breaker for rapid-fire excessive slow requests.
    # If we trip this breaker continually, it will log once per minute that it is broken
    def clip_recording?
      if @minute_count > MAX_PER_MINUTE
        if !@clipped_recording
          ScoutApm::Agent.instance.logger.info("Skipping future slow requests this minute, reached limit of #{MAX_PER_MINUTE}")
        end

        @clipped_recording = true
        true
      else
        false
      end
    end
  end
end
