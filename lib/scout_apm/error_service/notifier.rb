module ScoutApm
  module ErrorService
    class Notifier
      class << self
        def notify(data)
          @data = data
          serialized_data = {problem: data}.to_json
          return if ignore_exception?

          Thread.new do
            reporter = ScoutApm::Reporter.new(ScoutApm::Agent.instance.context, :errors)
            reporter.report(serialized_data, headers)
          end
        end

        private

        def ignore_exception?
          ScoutApm::Agent.instance.context.config.value('errors_ignored_exceptions').include?(@data["name"])
        end

        def headers
          {}
        end
      end
    end
  end
end
