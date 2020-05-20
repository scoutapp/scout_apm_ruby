module ScoutApm
  module ErrorService
    class Notifier
      class << self
        def notify(data)
          @data = data
          serialized_data = {problem: data}.to_json
          return if ignore_exception?
          repoter = ScoutApm::Reporter.new(ScoutApm::Agent.instance.context, :errors)
          reporter.report(serialized_data, headers)
        end

        private

        def ignore_exception?
          ScoutApm::Agent.instance.config.value('error_ignored_exceptions').include?(@data["name"])
        end
      end
    end
  end
end
