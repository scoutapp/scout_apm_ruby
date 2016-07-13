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
      enable_profiled_thread!

      store = if ScoutApm::Agent.instance.apm_enabled?
                ScoutApm::Agent.instance.store
              else
                ScoutApm::FakeStore.new
              end
      Thread.current[:scout_request] = TrackedRequest.new(store)
    end

    # TODO: This class is probably a slightly wrong place. This will add
    # threads that aren't real web threads.  For instance, a DB call during an
    # initializer, or a short lived thread spawned from an action.
    #
    # This could also go in TrackedRequest when we first call `web!` or
    # `job!`, and indicate it's a real request.
    def self.enable_profiled_thread!
      if ! Thread.current[:scout_profiled_thread]
        Thread.current[:scout_profiled_thread] = true
        ScoutApm::Instruments::Stacks.add_profiled_thread
      end
    end
  end
end
