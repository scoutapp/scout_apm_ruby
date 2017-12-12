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

      if req && (req.stopping? || req.recorded?)
        ScoutApm::Agent.instance.trace("RequestManager.find req is present, but stopping")
        nil
      else
        ScoutApm::Agent.instance.trace("RequestManager.find found request: #{req.object_id}")
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

      req = TrackedRequest.new(store)

      ScoutApm::Agent.instance.trace("RequestManager.create created new request: #{req.object_id}")

      Thread.current[:scout_request] = req
    end
  end
end
