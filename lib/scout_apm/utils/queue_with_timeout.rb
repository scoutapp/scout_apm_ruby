module ScoutApm
  module Utils
    class QueueWithTimeout
      attr_reader :max_size

      def initialize(max_size = nil)
        @mutex = Mutex.new
        @queue = []
        @max_size = max_size
        @received = ConditionVariable.new
      end

      # Add to the end of the Queue
      def <<(x)
        @mutex.synchronize do
          return false if full?
          @queue << x
          @received.signal
          return true
        end
      end

      # Add to the head of the queue, next to pop off
      def unshift(x)
        @mutex.synchronize do
          return false if full?
          @queue.unshift(x)
          @received.signal
          return true
        end
      end

      # Get the next value (typically, the one waiting the longest)
      def shift(blocking = false, timeout = nil)
        @mutex.synchronize do
          if blocking && timeout.nil?
            shift_blocking_no_timeout
          elsif blocking && @queue.empty? && timeout.to_f >= 0
            shift_blocking_with_timeout(timeout)
          else
            shift_non_blocking
          end
        end
      end

      def sized?
        ! max_size.nil?
      end

      def full?
        sized? && @queue.size >= max_size
      end

      def shift_blocking_no_timeout
        # wait indefinitely until there is an element in the queue
        while @queue.empty?
          @received.wait(@mutex)
        end

        @queue.shift
      end

      def shift_blocking_with_timeout(timeout)

        # wait for element or timeout
        timeout_time = timeout + ::Time.now.to_f
        while @queue.empty? && (remaining_time = timeout_time - ::Time.now.to_f) > 0
          @received.wait(@mutex, remaining_time)
        end

        # if we're still empty after the timeout, raise exception
        raise ThreadError, "queue empty" if @queue.empty?

        @queue.shift
      end

      def shift_non_blocking
        if @queue.empty?
          raise "queue empty"
        end

        @queue.shift
      end
    end
  end
end
