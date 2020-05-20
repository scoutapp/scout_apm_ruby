require "net/http"
require "net/https"
require "uri"

module ScoutApm
  module ErrorService
    API_VERSION = "1"
    NOTIFIER_NAME = "scout_apm_ruby"

    HEADERS = {
      "Content-type" => "application/json",
      "Accept" => "application/json"
    }

    # Used by SidekiqException or for manual calls
    def self.notify(exception, params = {})
      return if disabled?
      data = Data.rack_data(exception, params)
      Notifier.notify(data)
    end

    def self.enabled?
      ScoutApm::Agent.instance.context.config.value("errors_enabled")
    end

    def self.disabled?
      !enabled?
    end
  end
end
