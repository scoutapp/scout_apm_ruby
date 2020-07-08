module ScoutApm
  module ErrorService
    class Notifier
      class << self
        def notify(data)
          @data = data
          serialized_data = {:problem => data}.to_json

          Thread.new do
            reporter = ScoutApm::Reporter.new(ScoutApm::Agent.instance.context, :errors)
            reporter.report(serialized_data, headers)
          end
        end

        private

        def headers
          {}
        end
      end
    end
  end
end
