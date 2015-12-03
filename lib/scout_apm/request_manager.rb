# Request manager handles the threadlocal variable that holds the current
# request. If there isn't one, then create one

module ScoutApm
  class RequestManager
    def self.lookup
      find || create
    end

    def self.find
      req = Thread.current[:scout_request]

      if req.finished?
        nil
      else
        req
      end
    end

    def self.create
      Thread.current[:scout_request] = TrackedRequest.new
    end
  end
end
