# Request manager handles the threadlocal variable that holds the current
# request. If there isn't one, then create one.
#
# Under Rage (fiber-per-request concurrency), uses Fiber-local storage
# instead of Thread-local storage to isolate concurrent requests.

module ScoutApm
  class RequestManager
    STORAGE_KEY = :scout_request

    def self.lookup
      find || create
    end

    # Get the current request, detecting and not returning a stale request
    def self.find
      req = storage[STORAGE_KEY]

      if req && (req.stopping? || req.recorded?)
        nil
      else
        req
      end
    end

    # Create a new TrackedRequest object for this fiber/thread
    def self.create
      agent_context = ScoutApm::Agent.instance.context
      store = agent_context.store
      storage[STORAGE_KEY] = TrackedRequest.new(agent_context, store)
    end

    # Use Fiber-local storage under Rage (fiber-per-request),
    # Thread-local storage everywhere else (thread-per-request).
    def self.storage
      if defined?(::Rage) && !defined?(::Rails)
        Fiber
      else
        Thread.current
      end
    end
  end
end
