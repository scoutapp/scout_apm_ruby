# Contains the methods that instrument blocks of code. 
# 
# When a code block is wrapped inside #instrument(metric_name):
# * The #instrument method pushes a StackItem onto Store#stack
# * When a code block is finished, #instrument pops the last item off the stack and verifies it's the StackItem
#   we created earlier. 
# * Once verified, the metrics for the recording session are merged into the in-memory Store#metric_hash. The current scope
#   is also set for the metric (if Thread::current[:scout_scope_name] isn't nil).
module ScoutApm::Tracer
  def self.included(klass)
    klass.extend ClassMethods
  end
  
  module ClassMethods
    
    # Use to trace a method call, possibly reporting slow transaction traces to Scout. 
    def trace(metric_name, options = {}, &block)
      ScoutApm::Agent.instance.store.reset_transaction!      
      instrument(metric_name, options) do
        Thread::current[:scout_scope_name] = metric_name
        yield
        Thread::current[:scout_scope_name] = nil
      end
    end
    
    # Options:
    # - :scope => If specified, sets the sub-scope for the metric. We allow additional scope level. This is used
    # when rendering the transaction tree in the UI. 
    def instrument(metric_name, options={}, &block)
      # don't instrument if (1) NOT inside a transaction and (2) NOT a Controller metric.
      if !Thread::current[:scout_scope_name] and metric_name !~ /\AController\//
        return yield
      end
      if options.delete(:scope)
        Thread::current[:scout_sub_scope] = metric_name 
      end
      stack_item = ScoutApm::Agent.instance.store.record(metric_name)
      begin
        yield
      ensure
        Thread::current[:scout_sub_scope] = nil if Thread::current[:scout_sub_scope] == metric_name
        ScoutApm::Agent.instance.store.stop_recording(stack_item,options)
      end
    end
    
    def instrument_method(method,options = {})
      ScoutApm::Agent.instance.logger.info "Instrumenting #{method}"
      metric_name = options[:metric_name] || default_metric_name(method)
      return if !instrumentable?(method) or instrumented?(method,metric_name)
      class_eval instrumented_method_string(method, {:metric_name => metric_name, :scope => options[:scope]}), __FILE__, __LINE__
      
      alias_method _uninstrumented_method_name(method, metric_name), method
      alias_method method, _instrumented_method_name(method, metric_name)
    end
    
    private
    
    def instrumented_method_string(method, options)
      klass = (self === Module) ? "self" : "self.class"
      "def #{_instrumented_method_name(method, options[:metric_name])}(*args, &block)
        result = #{klass}.instrument(\"#{options[:metric_name]}\",{:scope => #{options[:scope] || false}}) do
          #{_uninstrumented_method_name(method, options[:metric_name])}(*args, &block)
        end
        result
      end"
    end
    
    # The method must exist to be instrumented.
    def instrumentable?(method)
      exists = method_defined?(method) || private_method_defined?(method)
      ScoutApm::Agent.instance.logger.warn "The method [#{self.name}##{method}] does not exist and will not be instrumented" unless exists
      exists
    end
    
    # +True+ if the method is already instrumented. 
    def instrumented?(method,metric_name)
      instrumented = method_defined?(_instrumented_method_name(method, metric_name))
      ScoutApm::Agent.instance.logger.warn "The method [#{self.name}##{method}] has already been instrumented" if instrumented
      instrumented
    end
    
    def default_metric_name(method)
      "Custom/#{self.name}/#{method.to_s}"
    end
    
    # given a method and a metric, this method returns the
    # untraced alias of the method name
    def _uninstrumented_method_name(method, metric_name)
      "#{_sanitize_name(method)}_without_scout_instrument_#{_sanitize_name(metric_name)}"
    end
    
    # given a method and a metric, this method returns the traced
    # alias of the method name
    def _instrumented_method_name(method, metric_name)
      name = "#{_sanitize_name(method)}_with_scout_instrument_#{_sanitize_name(metric_name)}"
    end
    
    # Method names like +any?+ or +replace!+ contain a trailing character that would break when
    # eval'd as ? and ! aren't allowed inside method names.
    def _sanitize_name(name)
      name.to_s.tr_s('^a-zA-Z0-9', '_')
    end
  end # ClassMethods
end # module Tracer