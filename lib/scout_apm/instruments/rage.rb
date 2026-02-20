# Instrument wrapper for the Rage framework.
#
# Follows the standard Scout instrument interface (initialize/install/installed?)
# so it can be managed by InstrumentManager. The actual instrumentation is done
# by RageTelemetryHandler, which is registered with Rage's telemetry system.

module ScoutApm
  module Instruments
    class Rage
      attr_reader :context

      def initialize(context)
        @context = context
        @installed = false
      end

      def installed?
        @installed
      end

      def install(prepend: false)
        return unless defined?(::Rage::Telemetry::Handler)
        return if @installed

        require 'scout_apm/instruments/rage_telemetry_handler'

        handler = ScoutApm::Instruments::RageTelemetryHandler.new
        ::Rage.config.telemetry.use(handler)

        @installed = true
        context.logger.info("Instrumenting Rage via Telemetry Handler")
      end
    end
  end
end
