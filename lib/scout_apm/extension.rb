module ScoutApm
  # This provides an abstraction which uses Module#prepend on Ruby that supports it, and provides a small meta-programming hack for Rubies that don't that achieves something very similar.
  module Extension
    if Module.respond_to?(:prepend)
      def apply(klass)
        ScoutApm::Agent.instance.context.logger.info "Instrumenting #{klass.inspect}"
    
        klass.prepend(self)
      end
    else
      def extensions_module_for(klass)
        klass.include(Module.new)
      end
      
      def apply(klass)
        ScoutApm::Agent.instance.context.logger.info "Instrumenting #{klass.inspect}"

        self.instance_methods.each do |name|
          original_method = klass.instance_method(name)
          wrapper_method = self.instance_method(name)
          
          parent = extensions_module_for(klass)
          
          parent.define_method(name) do |*args, &block|
            original_method.bind(self).call(*args, &block)
          end
          
          klass.define_method(name, wrapper_method)
          
          return klass
        end
      end
    end
  end
end
