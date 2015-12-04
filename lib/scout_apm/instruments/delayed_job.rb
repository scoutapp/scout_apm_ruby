module ScoutApm
  module Instruments
    class DelayedJob
      attr_reader :logger

      def initialize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true
        if defined?(::Delayed::Worker)
          ::Delayed::Worker.class_eval do
            include ScoutApm::Tracer
            include ScoutApm::Instruments::DelayedJobInstruments
            alias run_without_scout_instruments run
            alias run run_with_scout_instruments
          end
        end
      end
    end

    module DelayedJobInstruments
      def run_with_scout_instruments(job)
        job_handler = YAML.load(job.handler)
        klass = job_handler.object.name
        method = job_handler.method_name
        scout_method_name = "Job/#{klass}##{method}"
        queue = job.queue
        puts "########################### #{scout_method_name} - #{queue}"
        self.class.scout_apm_trace(scout_method_name) do
          run_without_scout_instruments(job)
        end
      end
    end
  end
end
