# Provide a background thread queue to do the processing of
# TrackedRequest objects, to remove it from the hot-path of returning a
# web response

module ScoutApm
  class BackgroundRecorder
    attr_reader :queue
    attr_reader :thread
    attr_reader :logger

    def initialize(logger)
      @logger = logger
      @queue = Queue.new
    end

    def start
      logger.info("Starting BackgroundRecorder")
      @thread = Thread.new(&method(:thread_func))
      self
    end

    def stop
      @thread.kill
    end

    def record!(request)
      start unless @thread.alive?
      @queue.push(request)
    end

    def thread_func
      while req = queue.pop
        begin
          logger.debug("recording in thread. Queue size: #{queue.size}")
          # For now, just proxy right back into the TrackedRequest object's record function
          req.record!
        rescue => e
          logger.warn("Error in BackgroundRecorder - #{e.message} : #{e.backtrace}")
        end
      end
    end
  end
end
