
# The store encapsolutes the logic that (1) saves instrumented data by Metric name to memory and (2) maintains a stack (just an Array)
# of instrumented methods that are being called. It's accessed via +ScoutApm::Agent.instance.store+.
module ScoutApm
  class Store

    # Limits the size of the metric hash to prevent a metric explosion.
    MAX_SIZE = 1000

    # Limit the number of slow transactions that we store metrics with to prevent writing too much data to the layaway file if there are are many processes and many slow slow_transactions.
    MAX_SLOW_TRANSACTIONS_TO_STORE_METRICS = 10

    attr_accessor :metric_hash
    attr_accessor :transaction_hash
    attr_accessor :stack
    attr_accessor :slow_transactions # array of slow transaction slow_transactions
    attr_reader :slow_transaction_lock

    def initialize
      @metric_hash = Hash.new
      # Stores aggregate metrics for the current transaction. When the transaction is finished, metrics
      # are merged with the +metric_hash+.
      @transaction_hash = Hash.new
      @stack = Array.new
      # ensure background thread doesn't manipulate transaction sample while the store is.
      @slow_transaction_lock = Mutex.new
      @slow_transactions = Array.new
    end

    # Called when the last stack item completes for the current transaction to clear
    # for the next run.
    def reset_transaction!
      Thread::current[:scout_apm_ignore_transaction] = nil
      Thread::current[:scout_apm_scope_name] = nil
      @transaction_hash = Hash.new
      @stack = Array.new
    end

    def ignore_transaction!
      Thread::current[:scout_apm_ignore_transaction] = true
    end

    # Called at the start of Tracer#instrument:
    # (1) Either finds an existing MetricStats object in the metric_hash or
    # initialize a new one. An existing MetricStats object is present if this +metric_name+ has already been instrumented.
    # (2) Adds a StackItem to the stack. This StackItem is returned and later used to validate the item popped off the stack
    # when an instrumented code block completes.
    def record(metric_name)
      item = ScoutApm::StackItem.new(metric_name)
      stack << item
      item
    end

    # Options:
    # * :scope - If specified, sets the sub-scope for the metric. We allow additional scope level. This is used
    # * uri - the request uri
    def stop_recording(sanity_check_item, options={})
      item = stack.pop
      stack_empty = stack.empty?

      # if ignoring the transaction, the item is popped but nothing happens.
      if Thread::current[:scout_apm_ignore_transaction]
        return
      end

      # unbalanced stack check - unreproducable cases have seen this occur. when it does, sets a Thread variable
      # so we ignore further recordings. +Store#reset_transaction!+ resets this.
      if item != sanity_check_item
        ScoutApm::Agent.instance.logger.warn "Scope [#{Thread::current[:scout_apm_scope_name]}] Popped off stack: #{item.inspect} Expected: #{sanity_check_item.inspect}. Aborting."
        ignore_transaction!
        return
      end

      duration = Time.now - item.start_time
      if last = stack.last
        last.children_time += duration
      end

      meta = ScoutApm::MetricMeta.new(item.metric_name, :desc => options[:desc])
      meta.scope = nil if stack_empty

      # add backtrace for slow calls ... how is exclusive time handled?
      if duration > ScoutApm::SlowTransaction::BACKTRACE_THRESHOLD and !stack_empty
        meta.extra = {:backtrace => ScoutApm::SlowTransaction.backtrace_parser(caller)}
      end

      stat = transaction_hash[meta] || ScoutApm::MetricStats.new(!stack_empty)
      stat.update!(duration,duration-item.children_time,options[:extra_metrics])
      transaction_hash[meta] = stat if store_metric?(stack_empty)

      # Uses controllers as the entry point for a transaction. Otherwise, stats are ignored.
      if stack_empty and meta.key_metric?
        aggs = aggregate_calls(transaction_hash.dup,meta)
        store_slow(options[:uri], transaction_hash.dup.merge(aggs), meta, stat)
        # deep duplicate
        duplicate = aggs.dup
        duplicate.each_pair do |k,v|
          duplicate[k.dup] = v.dup
        end
        merge_metrics(duplicate.merge({meta.dup => stat.dup})) # aggregrates + controller
      end
    end

    # TODO - Move more logic to SlowTransaction
    #
    # Limits the size of the transaction hash to prevent a large transactions. The final item on the stack
    # is allowed to be stored regardless of hash size to wrapup the transaction sample w/the parent metric.
    def store_metric?(stack_empty)
      transaction_hash.size < ScoutApm::SlowTransaction::MAX_SIZE or stack_empty
    end

    # Returns the top-level category names used in the +metrics+ hash.
    def categories(metrics)
      cats = Set.new
      metrics.keys.each do |meta|
        next if meta.scope.nil? # ignore controller
        if match=meta.metric_name.match(/\A([\w]+)\//)
          cats << match[1]
        end
      end # metrics.each
      cats
    end

    # Takes a metric_hash of calls and generates aggregates for ActiveRecord and View calls.
    def aggregate_calls(metrics,parent_meta)
      categories = categories(metrics)
      aggregates = {}
      categories.each do |cat|
        agg_meta=ScoutApm::MetricMeta.new("#{cat}/all")
        agg_meta.scope = parent_meta.metric_name
        agg_stats = ScoutApm::MetricStats.new
        metrics.each do |meta,stats|
          if meta.metric_name =~ /\A#{cat}\//
            agg_stats.combine!(stats)
          end
        end # metrics.each
        aggregates[agg_meta] = agg_stats unless agg_stats.call_count.zero?
      end # categories.each
      aggregates
    end

    SLOW_TRANSACTION_THRESHOLD = 2

    # Stores slow transactions. This will be sent to the server.
    def store_slow(uri, transaction_hash, parent_meta, parent_stat, options = {})
      @slow_transaction_lock.synchronize do
        if parent_stat.total_call_time >= SLOW_TRANSACTION_THRESHOLD
          slow_transaction = ScoutApm::SlowTransaction.new(uri,
                                                           parent_meta.metric_name,
                                                           parent_stat.total_call_time,
                                                           transaction_hash.dup,
                                                           ScoutApm::Context.current,
                                                           Thread::current[:scout_apm_trace_time],
                                                           Thread::current[:scout_apm_prof])
          @slow_transactions.push(slow_transaction)
          ScoutApm::Agent.instance.logger.debug "Slow transaction sample added. [URI: #{uri}] [Context: #{ScoutApm::Context.current.to_hash}] Array Size: #{@slow_transactions.size}"
        end
      end
    end

    # Finds or creates the metric w/the given name in the metric_hash, and updates the time. Primarily used to
    # record sampled metrics. For instrumented methods, #record and #stop_recording are used.
    #
    # Options:
    # :scope => If provided, overrides the default scope.
    # :exclusive_time => Sets the exclusive time for the method. If not provided, uses +call_time+.
    def track!(metric_name, call_time, options = {})
      meta = ScoutApm::MetricMeta.new(metric_name)
      meta.scope = options[:scope] if options.has_key?(:scope)
      stat = metric_hash[meta] || ScoutApm::MetricStats.new
      stat.update!(call_time,(options[:exclusive_time] || call_time),(options[:extra_metrics] || {}))
      metric_hash[meta] = stat
    end

    # Combines old and current data
    def merge_data(old_data)
      {
        :metrics           => merge_metrics(old_data[:metrics]),
        :slow_transactions => merge_slow_transactions(old_data[:slow_transactions])
      }
    end

    # Merges old and current data, clears the current in-memory metric hash, and returns
    # the merged data
    def merge_data_and_clear(old_data)
      merged = merge_data(old_data)
      self.metric_hash =  {}
      # TODO - is this lock needed?
      @slow_transaction_lock.synchronize do
        self.slow_transactions = []
      end
      merged
    end

    def merge_metrics(old_metrics)
      old_metrics.each do |old_meta,old_stats|
        if stats = metric_hash[old_meta]
          metric_hash[old_meta] = stats.combine!(old_stats)
        elsif metric_hash.size < MAX_SIZE
          metric_hash[old_meta] = old_stats
        end
      end
      metric_hash
    end

    # Merges slow_transactions together, removing transaction sample metrics from slow_transactions if the > MAX_SLOW_TRANSACTIONS_TO_STORE_METRICS
    def merge_slow_transactions(old_slow_transactions)
      # need transaction lock here?
      self.slow_transactions += old_slow_transactions
      if trim_slow_transactions = self.slow_transactions[MAX_SLOW_TRANSACTIONS_TO_STORE_METRICS..-1]
        ScoutApm::Agent.instance.logger.debug "Trimming metrics from #{trim_slow_transactions.size} slow_transactions."
        i = MAX_SLOW_TRANSACTIONS_TO_STORE_METRICS
        trim_slow_transactions.each do |sample|
          self.slow_transactions[i] = sample.clear_metrics!
        end
      end
      self.slow_transactions
    end
  end # class Store
end
