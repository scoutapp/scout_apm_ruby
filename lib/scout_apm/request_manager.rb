# Request manager handles the threadlocal variable that holds the current
# request. If there isn't one, then create one

module ScoutApm
  class RequestManager
    def self.lookup
      find || create
    end

    # Get the current Thread local, and detecting, and not returning a stale request
    def self.find
      req = Thread.current[:scout_request]

      if req && req.recorded?
        nil
      else
        req
      end
    end

    # Create a new TrackedRequest object for this thread
    def self.create
      store = if ScoutApm::Agent.instance.apm_enabled?
                ScoutApm::Agent.instance.store
              else
                ScoutApm::FakeStore.new
              end

      Thread.current[:scout_request] = SimpleDelegator.new(TrackedRequest.new(store))
    end

    def self.ignore_request!
      tracked_request = find

      if tracked_request
        ignored_request = IgnoredRequest.from_tracked_request(tracked_request)
        tracked_request.__setobj__(ignored_request)
      else
        Thread.current[:scout_request] = IgnoredRequest.from_nothing
      end
    end
  end
end
