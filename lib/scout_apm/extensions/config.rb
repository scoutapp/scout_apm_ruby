module ScoutApm
  module Extensions
    # Extensions can be configured to fan out data to additional services.
    class Config
      attr_accessor :transaction_callbacks
      attr_accessor :reporting_period_callbacks

      # Adds a new callback that runs after a transaction completes via +TrackedRequest#record!+.
      # These run inline during the request and thus should add minimal overhead and NOT make inline HTTP calls to outside services.
      # +callback+ must inherit from +ScoutApm::Extensions::TransactionCallbackBase+.
      def self.add_transaction_callback(callback)
        agent_context.extensions.transaction_callbacks << callback
      end

      # Adds call that runs when the per-minute report data is sent to Scout.
      # These run in a background thread so external HTTP calls are OK.
      # +callback+ must inherit from +ScoutApm::Extensions::ReportingPeriodCallbackBase+.
      def self.add_reporting_period_callback(callback)
        agent_context.extensions.reporting_period_callbacks << callback
      end

      # Runs each reporting period callback. 
      # Each callback runs inside a begin/rescue block so a broken callback doesn't prevent other
      # callbacks from executing or reporting data from being sent. 
      def self.run_reporting_period_callbacks(reporting_period,metadata)
        return unless agent_context.extensions.reporting_period_callbacks.any?

        agent_context.extensions.reporting_period_callbacks.each do |klass|
          begin
            klass.new(reporting_period, metadata).call
          rescue => e
            logger.warn "Error running reporting callback extension=#{klass}"
            logger.info e.message
            logger.debug e.backtrace
          end
        end
      end

      # Runs each transaction callback.
      # Each callback runs inside a begin/rescue block so a broken callback doesn't prevent other
      # callbacks from executing or the transaction from being recorded. 
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
        @reporting_period_callbacks = []
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