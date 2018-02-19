module ScoutApm
  module Transaction
    # Ignores the current request
    def self.ignore!
      ::ScoutApm::RequestManager.lookup.ignore_request!
    end

    # Renames the last Controller or Job layer
    def self.rename(name)
      ::ScoutApm::RequestManager.lookup.rename_request_layer(name)
    end
  end
end
