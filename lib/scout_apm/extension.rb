module ScoutApm
  # This provides an abstraction which uses Module#prepend on Ruby that supports it, and provides a small meta-programming hack for Rubies that don't that achieves something very similar.
  module Extension
    if Module.respond_to?(:prepend)
      def self.apply klass, &block
        # ScoutApm::Agent.instance.context.logger.info "Instrumenting #{klass.inspect}"
        
        extension = Module.new
        extension.module_eval(&block)
        klass.prepend(extension)
      end
    else
      def self.apply klass, &block
        # ScoutApm::Agent.instance.context.logger.info "Instrumenting #{klass.inspect}"

        wrapper = Module.new
        wrapper.module_eval(&block)

        extension = Module.new
        klass.send(:include, extension)

        wrapper.instance_methods.each do |name|
          original_method = klass.instance_method(name)
          klass.send(:undef_method, name)

          extension.send(:define_method, name) do |*args, &block|
            original_method.bind(self).call(*args, &block)
          end
        end

        klass.class_eval(&block)
      end
    end
  end
end
