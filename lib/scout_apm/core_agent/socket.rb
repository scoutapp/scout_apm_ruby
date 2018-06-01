require 'singleton'
require 'thread'

module ScoutApm
  module CoreAgent
    class Socket
      attr_reader :context

      def initialize(context)
        @context = context

        # Socket related
        @socket_path = context.config.value('socket_path')
        @socket = nil

        connect
        register
      end

      def send(command)
        socket_send(command)
      rescue => e
      end

      private

      def socket_send(command, async=false)
        msg = command.message

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
          true
        else
          # TODO read respnse back in to command
          read_response
        end
      end

      def message_length(body)
        return [body.bytesize].pack('N')
      end

      def read_response
        raw_size = @socket.recv(4)
        size = raw_size.unpack('N').first
        message = @socket.read(size)
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

      def logger
        context.logger
      end
    end
  end
end
