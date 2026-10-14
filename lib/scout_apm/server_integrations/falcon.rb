module ScoutApm
  module ServerIntegrations
    # Falcon preloads the app in a parent process, then forks worker processes
    # (and re-forks them whenever its supervisor restarts one). Each worker
    # serves many concurrent requests as fibers on a single thread.
    class Falcon
      attr_reader :logger

      def initialize(logger)
        @logger = logger
      end

      def name
        :falcon
      end

      def forking?
        true
      end

      def present?
        defined?(::Falcon) && File.basename($PROGRAM_NAME).start_with?("falcon")
      end

      # Start the agent in every forked child. Ruby >= 3.1 routes all forks
      # through Process._fork, so this also covers workers restarted later.
      def install
        if ::Process.respond_to?(:_fork)
          logger.info "Installing Falcon worker hook."
          ::Process.singleton_class.prepend(ForkHook)
        else
          logger.info "Falcon worker hook requires Ruby >= 3.1, the agent will start on the first request."
        end
      end

      # Don't start in the preloading parent: it serves no requests, and a
      # reporting thread caught mid-request when Falcon forks can leave locks
      # (OpenSSL, Net::HTTP) held forever in the child.
      def found?
        false
      end

      module ForkHook
        def _fork
          pid = super
          if pid == 0
            begin
              ScoutApm::Agent.instance.start
            rescue => e
              ScoutApm::Agent.instance.logger.warn("Failed to start in Falcon worker: #{e.message}")
            end
          end
          pid
        end
      end
    end
  end
end
