module ScoutApm
  module Utils
    class QueueWithTimeout
      attr_reader :max_size

      def initialize(max_size = nil)
        @data = Array.new
        @max_size = max_size

        @mutex = Mutex.new
        @notifier = ConditionVariable.new
      end

      # Add to the end of the Queue
      def <<(x)
        @mutex.synchronize do
          if full?
            puts "Full!"
            return false
          end

          @data << x
          puts "Added value to queue (#{self.object_id}) inside @data: #{@data.object_id}, length: #{@data.size}"
        end

        @notifier.broadcast
        true
      end

      # Add to the head of the queue, next to pop off
      def unshift(x)
        @mutex.synchronize do
          return false if full?
          @data.unshift(x)
          @notifier.broadcast
        end

        true
      end

      # Get the next value (typically, the one waiting the longest)
      def shift(blocking = false, timeout = nil)
        @mutex.synchronize do
          if blocking && timeout.nil?
            shift_blocking_no_timeout
          elsif blocking && @data.empty? && timeout.to_f >= 0
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
        sized? && @data.size >= max_size
      end

      def shift_blocking_no_timeout
        # wait indefinitely until there is an element in the queue
        while @data.empty?
          @notifier.wait(@mutex)
        end

        @data.shift
      end

      def shift_blocking_with_timeout(timeout)
        puts "Shift blocking w/ timeout (#{self.object_id}): #{timeout} - data size: #{@data.size}"

        # wait for element or timeout
        expiration = timeout + ::Time.now.to_f
        while @data.empty? && (remaining_time = expiration - ::Time.now.to_f) > 0
          puts "About to wait on mutex for #{remaining_time}"
          @notifier.wait(@mutex, remaining_time)
          puts " (#{self.object_id}) Woke up in timeout loop. data size: #{@data.size}, remaining time: #{expiration - ::Time.now.to_f}"
        end

        # if we're still empty after the timeout, raise exception
        if @data.empty?
          puts "Timeout ran out, but data is empty"
          raise ThreadError, "data empty"
        end

        v = @data.shift
        puts "Shifted off a value"
        v
      end

      def shift_non_blocking
        puts "(#{self.object_id}) Shift non blocking inside @data: #{@data.object_id}"
        if @data.empty?
          puts "Data was empty"
          raise "data empty"
        end

        @data.shift
      end
    end
  end
end
