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
        # Setup Tracer on AR::Base
        if Utils::KlassHelper.defined?("ActiveRecord::Base")
          ::ActiveRecord::Base.class_eval do
            include ::ScoutApm::Tracer
          end
        end

        # Install #log tracing
        if Utils::KlassHelper.defined?("ActiveRecord::ConnectionAdapters::AbstractAdapter")
          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
            include ::ScoutApm::Instruments::ActiveRecordInstruments
            include ::ScoutApm::Tracer
          end
        end

        if Utils::KlassHelper.defined?("ActiveRecord::Base")
          ::ActiveRecord::Base.class_eval do
            include ::ScoutApm::Instruments::ActiveRecordUpdateInstruments
          end
        end

        # Disabled until we can determine how to use Module#prepend in the
        # agent. Otherwise, this will cause infinite loops if NewRelic is
        # installed. We can't just use normal Module#include, since the
        # original methods don't call super the way Base#save does
        #
        #if Utils::KlassHelper.defined?("ActiveRecord::Relation")
        #  ::ActiveRecord::Relation.class_eval do
        #    include ::ScoutApm::Instruments::ActiveRecordRelationInstruments
        #  end
        #end

        if Utils::KlassHelper.defined?("ActiveRecord::Querying")
          ::ActiveRecord::Querying.module_eval do
            include ::ScoutApm::Tracer
            include ::ScoutApm::Instruments::ActiveRecordQueryingInstruments
          end
        end

        if Utils::KlassHelper.defined?("ActiveRecord::FinderMethods")
          ::ActiveRecord::FinderMethods.module_eval do
            include ::ScoutApm::Tracer
            include ::ScoutApm::Instruments::ActiveRecordFinderMethodsInstruments
          end
        end

        if Utils::KlassHelper.defined?("ActiveSupport::Notifications")
          ActiveSupport::Notifications.subscribe("instantiation.active_record") do |event_name, start, stop, uuid, payload|
            req = ScoutApm::RequestManager.lookup
            layer = req.current_layer
            if layer && layer.type == "ActiveRecord"
              layer.annotate_layer(payload)
            elsif layer
              ScoutApm::Agent.instance.logger.debug("Expected layer type: ActiveRecord, got #{layer && layer.type}")
            else
              # noop, no layer at all. We're probably ignoring this req.
            end
          end
        end
      rescue
        ScoutApm::Agent.instance.logger.warn "ActiveRecord instrumentation exception: #{$!.message}"
      end
    end

    # Contains ActiveRecord instrument, aliasing +ActiveRecord::ConnectionAdapters::AbstractAdapter#log+ calls
    # to trace calls to the database.
    ################################################################################
    # #log instrument.
    #
    # #log is very close to where AR calls out to the database itself.  We have access
    # to the real SQL, and an AR generated "name" for the Query
    #
    ################################################################################
    module ActiveRecordInstruments
      def self.included(instrumented_class)
        ScoutApm::Agent.instance.logger.info "Instrumenting #{instrumented_class.inspect}"
        instrumented_class.class_eval do
          unless instrumented_class.method_defined?(:log_without_scout_instruments)
            alias_method :log_without_scout_instruments, :log
            alias_method :log, :log_with_scout_instruments
          end
        end
      end

      def log_with_scout_instruments(*args, &block)
        # Extract data from the arguments
        sql, name = args
        metric_name = Utils::ActiveRecordMetricName.new(sql, name)
        desc = Utils::SqlSanitizer.new(sql)

        # Get current ScoutApm context
        req = ScoutApm::RequestManager.lookup
        current_layer = req.current_layer


        # If we call #log, we have a real query to run, and we've already
        # gotten through the cache gatekeeper. Since we want to only trace real
        # queries, and not repeated identical queries that just hit cache, we
        # mark layer as ignorable initially in #find_by_sql, then only when we
        # know it's a real database call do we mark it back as usable.
        #
        # This flag is later used in SlowRequestConverter to skip adding ignorable layers
        current_layer.annotate_layer(:ignorable => false) if current_layer

        # Either: update the current layer and yield, don't start a new one.
        if current_layer && current_layer.type == "ActiveRecord"
          # TODO: Get rid of call .to_s, need to find this without forcing a previous run of the name logic
          if current_layer.name.to_s == Utils::ActiveRecordMetricName::DEFAULT_METRIC
            current_layer.name = metric_name
            current_layer.desc = desc
          end

          log_without_scout_instruments(*args, &block)

        # OR: Start a new layer, we didn't pick up instrumentation earlier in the stack.
        else
          layer = ScoutApm::Layer.new("ActiveRecord", metric_name)
          layer.desc = desc
          req.start_layer(layer)
          begin
            log_without_scout_instruments(*args, &block)
          ensure
            req.stop_layer
          end
        end
      end
    end

    ################################################################################
    # Entry-point of instruments.
    #
    # We instrument both ActiveRecord::Querying#find_by_sql and
    # ActiveRecord::FinderMethods#find_with_associations.  These are early in
    # the chain of calls when you're using ActiveRecord.
    #
    # Later on, they will call into #log, which we also instrument, at which
    # point, we can fill in additional data gathered at that point (name, sql)
    #
    # Caveats:
    #   * We don't have a name for the query yet.
    #   * The query hasn't hit the cache yet. In the case of a cache hit, we
    #     won't hit #log, so won't get a name, leaving the misleading default.
    #   * One call here can result in several calls to #log, especially in the
    #     case where Rails needs to load the schema details for the table being
    #     queried.
    ################################################################################

    module ActiveRecordQueryingInstruments
      def self.included(instrumented_class)
        ScoutApm::Agent.instance.logger.info "Instrumenting ActiveRecord::Querying - #{instrumented_class.inspect}"
        instrumented_class.class_eval do
          unless instrumented_class.method_defined?(:find_by_sql_without_scout_instruments)
            alias_method :find_by_sql_without_scout_instruments, :find_by_sql
            alias_method :find_by_sql, :find_by_sql_with_scout_instruments
          end
        end
      end

      def find_by_sql_with_scout_instruments(*args, &block)
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName::DEFAULT_METRIC)
        layer.annotate_layer(:ignorable => true)
        req.start_layer(layer)
        req.ignore_children!
        begin
          find_by_sql_without_scout_instruments(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end

    module ActiveRecordFinderMethodsInstruments
      def self.included(instrumented_class)
        ScoutApm::Agent.instance.logger.info "Instrumenting ActiveRecord::FinderMethods - #{instrumented_class.inspect}"
        instrumented_class.class_eval do
          unless instrumented_class.method_defined?(:find_with_associations_without_scout_instruments)
            alias_method :find_with_associations_without_scout_instruments, :find_with_associations
            alias_method :find_with_associations, :find_with_associations_with_scout_instruments
          end
        end
      end

      def find_with_associations_with_scout_instruments(*args, &block)
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName::DEFAULT_METRIC)
        layer.annotate_layer(:ignorable => true)
        req.start_layer(layer)
        req.ignore_children!
        begin
          find_with_associations_without_scout_instruments(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end

    module ActiveRecordUpdateInstruments
      def save(*args, &block)
        model = self.class.name
        operation = self.persisted? ? "Update" : "Create"

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} #{operation}"))
        req.start_layer(layer)
        req.ignore_children!
        begin
          super(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end

      def save!(*args, &block)
        model = self.class.name
        operation = self.persisted? ? "Update" : "Create"

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} #{operation}"))
        req.start_layer(layer)
        req.ignore_children!
        begin
          super(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end

    module ActiveRecordRelationInstruments
      def self.included(instrumented_class)
        ::ActiveRecord::Relation.class_eval do
          alias_method :update_all_without_scout_instruments, :update_all
          alias_method :update_all, :update_all_with_scout_instruments

          alias_method :delete_all_without_scout_instruments, :delete_all
          alias_method :delete_all, :delete_all_with_scout_instruments

          alias_method :destroy_all_without_scout_instruments, :destroy_all
          alias_method :destroy_all, :destroy_all_with_scout_instruments
        end
      end

      def update_all_with_scout_instruments(*args, &block)
        model = self.name

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} Update"))
        req.start_layer(layer)
        req.ignore_children!
        begin
          update_all_without_scout_instruments(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end

      def delete_all_with_scout_instruments(*args, &block)
        model = self.name

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} Delete"))
        req.start_layer(layer)
        req.ignore_children!
        begin
          delete_all_without_scout_instruments(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end

      def destroy_all_with_scout_instruments(*args, &block)
        model = self.name

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} Delete"))
        req.start_layer(layer)
        req.ignore_children!
        begin
          destroy_all_without_scout_instruments(*args, &block)
        ensure
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end
  end
end
