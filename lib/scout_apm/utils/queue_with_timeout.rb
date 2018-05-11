module ScoutApm
class QueueWithTimeout
    attr_reader :max_size

    def initialize(max_size = nil)
      @mutex = Mutex.new
      @queue = []
      @max_size = max_size
      @received = ConditionVariable.new
    end
   
    def <<(x)
      @mutex.synchronize do
        return false if full?
        @queue << x
        @received.signal
        return true
      end
    end

    def unshift(x)
      @mutex.synchronize do
        return false if full?
        @queue.unshift(x)
        @received.signal
        return true
      end
    end

    def shift(blocking = false, timeout = nil)
      @mutex.synchronize do
        if blocking && timeout.nil?
          # wait indefinitely until there is an element in the queue
          while @queue.empty?
            @received.wait(@mutex)
          end
        elsif @queue.empty? && timeout.to_f >= 0
          # wait for element or timeout
          timeout_time = timeout + Time.now.to_f
          while @queue.empty? && (remaining_time = timeout_time - Time.now.to_f) > 0
            @received.wait(@mutex, remaining_time)
          end
          #if we're still empty after the timeout, raise exception
          raise ThreadError, "queue empty" if @queue.empty?
          @queue.shift
        else
          raise  ThreadError, "Invalid parameters in shift"
        end
      end
    end

    def full?
      @queue.size >= max_size
    end
  end
end