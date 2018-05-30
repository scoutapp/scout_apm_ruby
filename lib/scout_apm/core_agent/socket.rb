require 'singleton'

module ScoutApm
  module CoreAgent
    class Socket
      @@instance = nil

      attr_reader :logger
      attr_reader :context

      # Socket is a singleton
      def self.instance(options = {})
        @@instance ||= self.new(options)
      end

      def initialize(context)
        @context = context
        @logger = context.logger

        # Socket related
        @socket_path = context.config.value('socket_path')
        @socket = nil

        # Threading control related
        @started_event = false
        @stop_event = false
        @stopped_event = false

        # Command queues
        @command_queue = ScoutApm::Utils::QueueWithTimeout.new
        @run_lock = Mutex.new
      end

      def running?
        return @started_event
      end

      def stop
        if @started_event
          @stop_event = true
          ConditionVariable.new.wait(@run_lock, 2)
          if @stopped_event
            return true
          else
            logger.debug('CoreAgentSocket Failed to stop thread within timeout!')
            return false
          end
        else
            return true
        end
      end

      def run
        Thread.new do
          if !@run_lock.try_lock
            logger.debug('CoreAgentSocket thread failed to acquire run lock.')
            return nil
          end

          begin
            @started_event = true
            connect
            register
            while true do
              body = nil
              begin
                body = @command_queue.shift(false, 1)
              rescue ThreadError
                next
              end

              if body
                result = socket_send(body)
                if !result
                  # Something was wrong with the socket.
                  @command_queue.unshift(body)
                  disconnect
                  connect
                  register
                end
              end

              # Check for stop event after a read from the queue. This is to
              # allow you to open a socket, immediately send to it, and then
              # stop it. We do this in the Metadata send at application start
              # time
              if @stop_event
                logger.debug("CoreAgentSocket thread stopping.")
                break
              end
            end
          ensure
            @run_lock.unlock
            @stop_event = false
            @started_event = false
            @stopped_event = true
            logger.debug("CoreAgentSocket thread stopped.")
          end # begin
        end
      end

      def send(command)
        unless @command_queue << command
          # TODO mark the command as not queued?
          logger.debug('CoreAgentSocket error on send: queue full')
        end
      end

      private

      def socket_send(command, async=true)
        msg = command.message()

        begin
          data = JSON.generate(msg)
        rescue StandardError => e
          logger.debug("Exception when serializing command message: #{e}")
          return false
        end

        begin
          @socket.send(message_length(data), 0)
          @socket.send(data.b, 0)
        rescue StandardError => e
          logger.debug("CoreAgentSocket exception on socket_send: #{e}")
          return nil
        end

        if async
          return true
        else
          # TODO read respnse back in to command
          return read_response
        end
      end

      def message_length(body)
        return [body.bytesize].pack('N')
      end

      def read_response
        raw_size = @socket.recvfrom(4)
        size = raw_size.unpack('N').first
        message = @socket.recvfrom(size)
        return message
      rescue StandardError => e
        logger.debug("CoreAgentSocket error on read response: #{e}")
        return nil
      end

      def register
        socket_send(
          ScoutApm::CoreAgent::RegisterCommand.new(
            context.config.value('name'),
            context.config.value('key')))
      end

      def connect(connect_attempts=5, retry_wait_secs=1)
        (1..connect_attempts).each do |attempt|
          logger.debug("CoreAgentSocket attempt #{attempt}, connecting to #{@socket_path}")
          begin
            if @socket = UNIXSocket.new(@socket_path)
              #secs = Integer(1)
              #usecs = Integer(1 * 1_000_000)
              #optval = [secs, usecs].pack("l_2")
              #@socket.setsockopt Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, optval
              #@socket.setsockopt Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, optval
              logger.debug('CoreAgentSocket is connected')
              return true
            end
          rescue StandardError=> e
            logger.debug("CoreAgentSocket connection error: #{e}")
            return false if attempt >= connect_attempts
          end
          sleep(retry_wait_secs)
        end
        logger.debug("CoreAgentSocket connection error: could not connect after #{connect_attempts} attemps")
        return false
      end

      def disconnect
        logger.debug("CoreAgentSocket disconnecting from #{@socket_path}")
        @socket.close
      rescue StandardError => e
        logger.debug("CoreAgentSocket exception on disconnect: #{e}")
      end
    end
  end
end
