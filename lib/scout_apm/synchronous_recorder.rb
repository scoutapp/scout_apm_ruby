# Provide a synchronous approach to recording TrackedRequests
# Doesn't attempt to background the work, or do it elsewhere. It happens
# inline, in the caller thread right when record! is called

module ScoutApm
  class SynchronousRecorder
    attr_reader :logger

    def initialize(logger)
      @logger = logger
    end

    def start
      # nothing to do
      self
    end

    def stop
      # nothing to do
    end

    def record!(request)
      request.record!
    end
  end
end
