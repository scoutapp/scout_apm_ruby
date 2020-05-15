require "net/http"
require "net/https"
require "uri"

require "scout_apm/error_service/version"
require "scout_apm/error_service/config"
require "scout_apm/error_service/notifier"
require "scout_apm/error_service/rack"

# Use Rack Middleware for Rails >= 3
require "scout_apm/error_service/railtie" if defined?(Rails::Railtie)
# Background Worker Middleware
require "scout_apm/error_service/sidekiq" if defined?(Sidekiq)

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
      Config.enabled_environments.include?(Data.application_environment)
    end

    def self.disabled?
      !enabled?
    end
  end
end
