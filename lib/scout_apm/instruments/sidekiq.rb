module ScoutApm
  module Instruments
    class Sidekiq
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
        if defined?(::Sidekiq::Processor)
          ::Sidekiq::Processor.class_eval do
            include ScoutApm::Tracer
            include ScoutApm::Instruments::SidekiqInstruments
            alias execute_job_without_scout_instruments execute_job
            alias execute_job execute_job_with_scout_instruments
          end
        end
      end
    end

    module SidekiqInstruments
      def execute_job_with_scout_instruments(worker, cloned_args)
        puts "###################################### instrumented"
        scout_method_name = "Job/#{cloned_args.first["job_class"]}"
        self.class.scout_apm_trace(scout_method_name) do
          execute_job_without_scout_instruments(worker, cloned_args)
        end
      end
    end
  end
end
