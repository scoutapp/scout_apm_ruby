module ScoutApm
  # Makes the agent safe across +fork()+.
  #
  # The agent runs several background threads (metrics worker, error-service
  # worker, async recorder, app-server-load reporter). Threads are not inherited
  # by a forked child, and worse, a thread that is mid-operation (holding a lock
  # in the resolver, OpenSSL, malloc, the logger, ...) at the instant of +fork()+
  # leaves the child holding that lock with no thread alive to release it -- an
  # intermittent boot deadlock. Forking app servers (Puma cluster / preload,
  # Unicorn) start the agent in the master and then fork, hitting exactly this.
  #
  # We cannot reliably detect "this process is about to fork" at boot (e.g. under
  # `rails server`, Puma has not configured itself yet when our Railtie runs), so
  # instead we hook +Process._fork+ -- invoked by every +Kernel#fork+ /
  # +Process.fork+, including Puma's worker forks -- and:
  #
  #   * before the fork: stop the agent's threads so none is alive at fork time
  #   * after the fork (in BOTH parent and child): restart them
  #
  # Restarting on both sides keeps monitoring alive in the surviving parent (an
  # app may fork for reasons unrelated to a web worker) and gives each child a
  # fresh, working set of threads.
  #
  # +Process._fork+ exists only on Ruby >= 3.1, so this is a no-op on older
  # Rubies, which keep the previous mitigations (Puma before_worker_boot hook,
  # first-request middleware start).
  module ForkSafety
    @installed = false

    def self.install
      return if @installed
      return unless Process.respond_to?(:_fork)

      Process.singleton_class.prepend(ProcessHook)
      @installed = true
    end

    def self.installed?
      @installed
    end

    # Parent side, just before the actual fork.
    def self.prepare_for_fork
      ScoutApm::Agent.instance.stop_threads_for_fork
    rescue => e
      log("Error preparing for fork: #{e.message}")
    end

    # Runs in both the parent and the child after the fork returns.
    def self.complete_fork
      ScoutApm::Agent.instance.restart_after_fork
    rescue => e
      log("Error restarting after fork: #{e.message}")
    end

    def self.log(message)
      ScoutApm::Agent.instance.context.logger.debug("[ForkSafety] #{message}")
    rescue
      # Never let logging failures escape into the host's fork path.
    end

    module ProcessHook
      # +super+ (the real fork) is called exactly once and outside any rescue, so
      # the agent's bookkeeping can never prevent or duplicate the host's fork.
      def _fork
        ScoutApm::ForkSafety.prepare_for_fork
        pid = super
        ScoutApm::ForkSafety.complete_fork
        pid
      end
    end
  end
end
