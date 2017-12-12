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
          ScoutApm::Agent.instance.trace("ActiveRecord.install setting up initializer")
          Rails.configuration.after_initialize do
            ScoutApm::Agent.instance.trace("ActiveRecord.install running initializer")
            add_instruments
          end
        else
          ScoutApm::Agent.instance.trace("ActiveRecord.install no initializer, adding immediately")
          add_instruments
        end
      end

      def add_instruments
        # Setup Tracer on AR::Base
        if Utils::KlassHelper.defined?("ActiveRecord::Base")
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Base found, including ScoutApm::Tracer")
          ::ActiveRecord::Base.class_eval do
            include ::ScoutApm::Tracer
          end
        else
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Base not found")
        end

        # Install #log tracing
        if Utils::KlassHelper.defined?("ActiveRecord::ConnectionAdapters::AbstractAdapter")
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::AbstractAdapter found, including ScoutApm::Instruments::ActiveRecordInstruments and ScoutApm::Tracer")
          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
            include ::ScoutApm::Instruments::ActiveRecordInstruments
            include ::ScoutApm::Tracer
          end
        else
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::AbstractAdapter not found")
        end

        if Utils::KlassHelper.defined?("ActiveRecord::Base")
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Base found, including ActiveRecordUpdateInstruments")
          ::ActiveRecord::Base.class_eval do
            include ::ScoutApm::Instruments::ActiveRecordUpdateInstruments
          end
        else
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Base not found")
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
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Querying found, including Tracer and ActiveRecordQueryingInstruments")
          ::ActiveRecord::Querying.module_eval do
            include ::ScoutApm::Tracer
            include ::ScoutApm::Instruments::ActiveRecordQueryingInstruments
          end
        else
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Querying not found")
        end

        if Utils::KlassHelper.defined?("ActiveRecord::FinderMethods")
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::FinderMethods found, including Tracer and ActiveRecordFinderMethodsInstruments")
          ::ActiveRecord::FinderMethods.module_eval do
            include ::ScoutApm::Tracer
            include ::ScoutApm::Instruments::ActiveRecordFinderMethodsInstruments
          end
        else
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::FinderMethods not found")
        end

        if Utils::KlassHelper.defined?("ActiveSupport::Notifications")
          ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Notification found, setting up subscriber")
          ActiveSupport::Notifications.subscribe("instantiation.active_record") do |event_name, start, stop, uuid, payload|
            ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Notification subscriber fired")
            req = ScoutApm::RequestManager.lookup
            layer = req.current_layer

            if layer && layer.type == "ActiveRecord"
              ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Notification layer was AR: LID(#{layer.object_id}), annotating with #{payload.inspect}")
              layer.annotate_layer(payload)
            elsif layer
              ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Notification layer was *NOT* AR: LID(#{layer.object_id})")
              ScoutApm::Agent.instance.logger.debug("Expected layer type: ActiveRecord, got #{layer && layer.type}")
            else
              # noop, no layer at all. We're probably ignoring this req.
              ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments ActiveRecord::Notification layer was missing entirely")
            end
          end
        end
      rescue
        ScoutApm::Agent.instance.trace("ActiveRecord.add_instruments EXCEPTION: #{$!.message} -- #{$!.backtrace}")
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
        ScoutApm::Agent.instance.trace("ActiveRecordInstruments.included into #{instrumented_class.inspect}")
        ScoutApm::Agent.instance.logger.info "Instrumenting #{instrumented_class.inspect}"
        instrumented_class.class_eval do
          if instrumented_class.method_defined?(:log_without_scout_instruments)
            ScoutApm::Agent.instance.trace("ActiveRecordInstruments.included -- log_without_scout_instruments was already defined")
          else
            ScoutApm::Agent.instance.trace("ActiveRecordInstruments.included -- alias method log_without_scout_instruments")
            alias_method :log_without_scout_instruments, :log
            alias_method :log, :log_with_scout_instruments
          end
        end
      end

      def log_with_scout_instruments(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments start: #{args.inspect}, block? #{block_given?}")

        # Extract data from the arguments
        sql, name = args
        metric_name = Utils::ActiveRecordMetricName.new(sql, name)
        desc = Utils::SqlSanitizer.new(sql)

        # Get current ScoutApm context
        req = ScoutApm::RequestManager.lookup
        current_layer = req.current_layer

        ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments sql: #{sql}, name: #{name}, desc: #{desc}, LID(#{current_layer.object_id}) annotations: (#{current_layer.annotations})", :skip_backtrace)

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
          ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments was an AR layer")
          # TODO: Get rid of call .to_s, need to find this without forcing a previous run of the name logic
          if current_layer.name.to_s == Utils::ActiveRecordMetricName::DEFAULT_METRIC
            ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments LID(#{current_layer.object_id}) updating the name and desc to #{metric_name}", :skip_backtrace)
            current_layer.name = metric_name
            current_layer.desc = desc
          else
            ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments LID(#{current_layer.object_id}) NOT updating the name and desc - already named: #{current_layer.name}", :skip_backtrace)
          end


          ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments calling log_without_scout_instruments")
          log_without_scout_instruments(*args, &block)

        # OR: Start a new layer, we didn't pick up instrumentation earlier in the stack.
        else
          ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments was NOT an AR layer, was: LID(#{current_layer.object_id}) - #{current_layer.type}. Starting a new one", :skip_backtrace)
          layer = ScoutApm::Layer.new("ActiveRecord", metric_name)
          layer.desc = desc
          req.start_layer(layer)
          begin
            ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments calling log_without_scout_instruments", :skip_backtrace)
            log_without_scout_instruments(*args, &block)
          ensure
            ScoutApm::Agent.instance.trace("ActiveRecordInstruments.log_with_scout_instruments stopping layer LID(#{layer.object_id})", :skip_backtrace)
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
        ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.included into #{instrumented_class.inspect}")
        instrumented_class.class_eval do
          if instrumented_class.method_defined?(:find_by_sql_without_scout_instruments)
            ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.included find_by_sql_without_scout_instruments was already defined")
          else
            ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.included find_by_sql being aliased")
            alias_method :find_by_sql_without_scout_instruments, :find_by_sql
            alias_method :find_by_sql, :find_by_sql_with_scout_instruments
          end
        end
      end

      def find_by_sql_with_scout_instruments(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.find_by_sql_with_scout_instruments called with #{args.inspect}, block? #{block_given?}")
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName::DEFAULT_METRIC)
        layer.annotate_layer(:ignorable => true)
        req.start_layer(layer)
        req.ignore_children!
        ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.find_by_sql_with_scout_instruments started ignorable layer: LID(#{layer.object_id})", :skip_backtrace)

        begin
          ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.find_by_sql_with_scout_instruments calling find_by_sql_without_scout_instruments", :skip_backtrace)
          find_by_sql_without_scout_instruments(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordQueryingInstruments.find_by_sql_with_scout_instruments stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end

    module ActiveRecordFinderMethodsInstruments
      def self.included(instrumented_class)
        ScoutApm::Agent.instance.logger.info "Instrumenting ActiveRecord::FinderMethods - #{instrumented_class.inspect}"
        ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.included into #{instrumented_class.inspect}")
        instrumented_class.class_eval do
          if instrumented_class.method_defined?(:find_with_associations_without_scout_instruments)
            ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.included find_with_associations_without_scout_instruments already defined")
          else
            ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.included find_with_associations_without_scout_instruments being aliased")
            alias_method :find_with_associations_without_scout_instruments, :find_with_associations
            alias_method :find_with_associations, :find_with_associations_with_scout_instruments
          end
        end
      end

      def find_with_associations_with_scout_instruments(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.find_with_associations_with_scout_instruments called with #{args.inspect}, block? #{block_given?}")
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName::DEFAULT_METRIC)
        layer.annotate_layer(:ignorable => true)
        req.start_layer(layer)
        req.ignore_children!

        ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.find_with_associations_with_scout_instruments started ignorable layer: LID(#{layer.object_id})", :skip_backtrace)
        begin
          ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.find_with_associations_with_scout_instruments calling find_with_associations_without_scout_instruments", :skip_backtrace)
          find_with_associations_without_scout_instruments(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordFinderMethodsInstruments.find_with_associations_with_scout_instruments stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end

    module ActiveRecordUpdateInstruments
      def save(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save called with #{args.inspect} and block? #{block_given?}")
        model = self.class.name
        operation = self.persisted? ? "Update" : "Create"

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} #{operation}"))
        req.start_layer(layer)
        req.ignore_children!

        ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save starting layer LID(#{layer.object_id})", :skip_backtrace)
        begin
          ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save calling super", :skip_backtrace)
          super(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end

      def save!(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save! called with #{args.inspect} and block? #{block_given?}")
        model = self.class.name
        operation = self.persisted? ? "Update" : "Create"

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} #{operation}"))
        req.start_layer(layer)
        req.ignore_children!

        ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save! starting layer LID(#{layer.object_id})", :skip_backtrace)
        begin
          ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save! calling super", :skip_backtrace)
          super(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordUpdateInstruments.save! stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end

    module ActiveRecordRelationInstruments
      def self.included(instrumented_class)
        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.included into #{instrumented_class.inspect}")

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
        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.update_all_with_scout_instruments called with #{args.inspect} and block? #{block_given?}")
        model = self.name

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} Update"))
        req.start_layer(layer)
        req.ignore_children!

        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.update_all_with_scout_instruments starting layer LID(#{layer.object_id})", :skip_backtrace)
        begin
          update_all_without_scout_instruments(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.update_all_with_scout_instruments stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end

      def delete_all_with_scout_instruments(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.delete_all_with_scout_instruments called with #{args.inspect} and block? #{block_given?}")
        model = self.name

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} Delete"))
        req.start_layer(layer)
        req.ignore_children!
        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.delete_all_with_scout_instruments starting layer LID(#{layer.object_id})", :skip_backtrace)
        begin
          delete_all_without_scout_instruments(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.delete_all_with_scout_instruments stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end

      def destroy_all_with_scout_instruments(*args, &block)
        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.destroy_all_with_scout_instruments called with #{args.inspect} and block? #{block_given?}")
        model = self.name

        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("ActiveRecord", Utils::ActiveRecordMetricName.new("", "#{model} Delete"))
        req.start_layer(layer)
        req.ignore_children!
        ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.destroy_all_with_scout_instruments starting layer LID(#{layer.object_id})", :skip_backtrace)
        begin
          destroy_all_without_scout_instruments(*args, &block)
        ensure
          ScoutApm::Agent.instance.trace("ActiveRecordRelationInstruments.destroy_all_with_scout_instruments stopping layer LID(#{layer.object_id})", :skip_backtrace)
          req.acknowledge_children!
          req.stop_layer
        end
      end
    end
  end
end
