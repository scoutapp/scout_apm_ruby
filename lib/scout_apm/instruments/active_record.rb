require 'scout_apm/utils/sql_sanitizer'

module ScoutApm
  module Instruments
    class ActiveRecord
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

        if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3 && ::Rails.respond_to?(:configuration)
          Rails.configuration.after_initialize do
            add_instruments
          end
        else
          add_instruments
        end
      end

      def add_instruments
        if defined?(::ActiveRecord) && defined?(::ActiveRecord::Base)
          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
            include ::ScoutApm::Instruments::ActiveRecordInstruments
            include ::ScoutApm::Tracer
          end

          ::ActiveRecord::Base.class_eval do
            include ::ScoutApm::Tracer
          end
        end
      rescue
        ScoutApm::Agent.instance.logger.warn "ActiveRecord instrumentation exception: #{$!.message}"
      end
    end

    # Contains ActiveRecord instrument, aliasing +ActiveRecord::ConnectionAdapters::AbstractAdapter#log+ calls
    # to trace calls to the database.
    module ActiveRecordInstruments
      def self.included(instrumented_class)
        ScoutApm::Agent.instance.logger.info "Instrumenting #{instrumented_class.inspect}"
        instrumented_class.class_eval do
          unless instrumented_class.method_defined?(:log_without_scout_instruments)
            alias_method :log_without_scout_instruments, :log
            alias_method :log, :log_with_scout_instruments
            protected :log
          end
        end
      end # self.included

      def log_with_scout_instruments(*args, &block)
        sql, name = args
        self.class.instrument("ActiveRecord",
                              Utils::ActiveRecordMetricName.new(sql, name).metric_name,
                              :desc => Utils::SqlSanitizer.new(sql).to_s ) do
          log_without_scout_instruments(sql, name, &block)
        end
      end
    end # module ActiveRecordInstruments
  end
end
