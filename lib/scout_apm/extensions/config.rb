module ScoutApm
  module Extensions
    # Extensions can be configured to fan out data to additional services.
    class Config
      attr_accessor :transaction_callbacks
      attr_accessor :reporting_callbacks

      # Adds a new +layer_converter+ that should run following a transaction being recorded in +TrackedRequest+.
      # These run inline during the request and thus should add minimal overhead and NOT make inline HTTP calls to outside services.
      # +layer_conveter+ must inherit from +ScoutApm::LayerConverters::ConverterBase+.
      def self.add_transaction_callback(layer_converter)
        agent_context.extensions.transaction_callbacks << layer_converter
      end

      # Adds a new reporter that should run when the per-minute report data is sent to Scout.
      # These run in a background thread so external HTTP calls are OK.
      # +reporter+ must inherit from +ScoutApm::Reporter::Base+.
      def self.add_reporting_callback(reporter)
        agent_context.extensions.reporting_callbacks << reporter
      end

      def self.run_reporting_callbacks(reporting_period,metadata)
        return unless agent_context.extensions.reporting_callbacks.any?

        agent_context.extensions.reporting_callbacks.each do |klass|
          begin
            klass.new(reporting_period, metadata).call
          rescue => e
            logger.warn "Error running reporting callback extension=#{klass}"
            logger.info e.message
            logger.debug e.backtrace
          end
        end
      end

      def self.run_transaction_callbacks(converter_results,context,scope_layer)
        # It looks like layer_finder.scope = nil when a Sidekiq job is retried
        return unless scope_layer
        return unless agent_context.extensions.transaction_callbacks.any?

        agent_context.extensions.transaction_callbacks.each do |klass|
          begin
            klass.new(converter_results,context,scope_layer).call
          rescue => e
            logger.warn "Error running transaction callback extension=#{klass}"
            logger.info e.message
            logger.debug e.backtrace
          end
        end
      end

      def initialize
        @transaction_callbacks = []
        @reporting_callbacks = []
      end

      def self.agent_context
        ScoutApm::Agent.instance.context
      end

      def self.logger
        agent_context.logger
      end

    end
  end
end