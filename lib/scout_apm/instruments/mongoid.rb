module ScoutApm
  module Instruments
    class Mongoid
      attr_reader :logger

      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        # Mongoid versions that use Moped should instrument Moped.
        if defined?(::Mongoid) and !defined?(::Moped)
          ScoutApm::Agent.instance.logger.info "Instrumenting Mongoid"

          ::Mongoid::Collection.class_eval do
            include ScoutApm::Tracer
            (::Mongoid::Collections::Operations::ALL - [:<<, :[]]).each do |method|
              instrument_method method, :metric_name => "MongoDB/\#{@klass}/#{method}"
            end
          end
        end

      end
    end
  end
end

