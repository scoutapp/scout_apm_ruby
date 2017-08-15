# Provides helpers to wrap sections of code in instrumentation using Ruby 2.0 Prepend approach

module ScoutApm
  module TracerPrepend
    def self.included(klass)
      klass.extend ClassMethods
    end

    module ClassMethods
      # Type: the Layer type - "View" or similar
      # Name: specific name - "users/_gravatar". The object must respond to "#to_s". This allows us to be more efficient - in most cases, the metric name isn't needed unless we are processing a slow transaction.
      # A Block: The code to be instrumented
      #
      # Options:
      # * :ignore_children - will not instrument any method calls beneath this call. Example use case: InfluxDB uses Net::HTTP, which is instrumented. However, we can provide more specific data if we know we're doing an influx call, so we'd rather just instrument the Influx call and ignore Net::HTTP.
      #   when rendering the transaction tree in the UI.
      # * :desc - Additional capture, SQL, or HTTP url or similar
      # * :scope - set to true if you want to make this layer a subscope
      def instrument_method(method_name, options = {})
        mod = create_instrumented_module(method_name, options)
        self.prepend(mod)
      end

      private

      # prepend this module into the class you'd like to instrument
      def create_instrumented_module(method_name, options)
        ScoutApm::Agent.instance.logger.info "Instrumenting #{method_name}"
        type = options[:type] || "Custom"
        name = options[:name] || "#{self.name}/#{method_name.to_s}"

        Module.new do
          define_method method_name do |*args, &block|
            resolved_name = name.respond_to?(:call) ? name.call(self, args) : name

            layer = ScoutApm::Layer.new(type, resolved_name)
            layer.desc = options[:desc] if options[:desc]
            layer.subscopable!          if options[:scope]

            req = ScoutApm::RequestManager.lookup
            req.start_layer(layer)
            req.ignore_children! if options[:ignore_children]

            begin
              super(*args, &block)
            ensure
              req.acknowledge_children! if options[:ignore_children]
              req.stop_layer
            end
          end
        end
      end
    end
  end
end
