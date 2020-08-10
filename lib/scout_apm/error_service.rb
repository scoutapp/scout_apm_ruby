require "net/http"
require "net/https"
require "uri"

module ScoutApm
  module ErrorService
    API_VERSION = "1"

    # Public API to force a given exception to be captured.
    # Still obeys the ignore list
    # Used internally by SidekiqException
    def self.capture(exception, params = {})
      return unless enabled?
      return if ScoutApm::Agent.instance.context.ignored_exceptions.ignore?(exception)

      context.errors_buffer.capture(exception, env)
    end

    def self.enabled?
      ScoutApm::Agent.instance.context.config.value("errors_enabled")
    end
  end
end
