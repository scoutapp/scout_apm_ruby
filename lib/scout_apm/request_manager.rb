# Request manager handles the threadlocal variable that holds the current
# request. If there isn't one, then create one

module ScoutApm
  class RequestManager
    def self.lookup
      find || create
    end

    # Get the current Thread local, detecting and not returning a stale request,
    # nor a request that belongs to a different thread.
    def self.find
      req = Thread.current[:scout_request]
      return nil unless req

      # ActionController::Live runs the controller action in a child thread and
      # copies the parent thread's raw Thread.current locals (including
      # :scout_request) into it. Without this check the parent (Rack) thread and
      # the child (streaming) thread would share and concurrently mutate a single
      # TrackedRequest -- racing on @layers/@stopping -- which corrupts the layer
      # stack, drops the transaction, and leaks layers across requests. If the
      # resident request was created on a different thread, treat it as absent so
      # lookup creates a fresh one owned by this thread.
      if req.creating_thread_id != Thread.current.object_id
        # [SCOUT_DIAG] Probe B. Confirms the fix is actually engaging in
        # production: a thread inherited another thread's request (Live child)
        # and we're handing it a fresh one instead of letting it race.
        begin
          ScoutApm::Agent.instance.context.logger.info(
            "[SCOUT_DIAG] FRESH-REQ-FOR-CHILD-THREAD " \
            "creating_thread=#{req.creating_thread_id} current_thread=#{Thread.current.object_id}"
          )
        rescue => e
          # never let diagnostics break request lookup
        end
        return nil
      end

      if req.stopping? || req.recorded?
        nil
      else
        req
      end
    end

    # Create a new TrackedRequest object for this thread
    # XXX: Figure out who is in charge of creating a `FakeStore` - previously was here
    def self.create
      agent_context = ScoutApm::Agent.instance.context
      store = agent_context.store
      Thread.current[:scout_request] = TrackedRequest.new(agent_context, store)
    end
  end
end
