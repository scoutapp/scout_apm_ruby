# Provides helpers to wrap sections of code in instrumentation
#
# The manual approach is to wrap your code in a call like:
#     `instrument("View", "users/index") do ... end`
#
# The monkey-patching approach does this for you:
#     `instrument_method(:my_render, :type => "View", :name => "users/index)`

module ScoutApm
  module Tracer
    def self.included(klass)
      klass.extend ClassMethods
    end

    module ClassMethods
      # Type: the Layer type - "View" or similar
      # Name: specific name - "users/_gravatar"
      # A Block: The code to be instrumented
      #
      # Options:
      # * :ignore_children - will not instrument any method calls beneath this call. Example use case: InfluxDB uses Net::HTTP, which is instrumented. However, we can provide more specific data if we know we're doing an influx call, so we'd rather just instrument the Influx call and ignore Net::HTTP.
      #   when rendering the transaction tree in the UI.
      # * :desc - Additional capture, SQL, or HTTP url or similar
      def instrument(type, name, options={}) # Takes a block
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new(type, name)
        req.start_layer(layer)
        layer.desc = options[:desc] if options[:desc]
        req.ignore_children! if options[:ignore_children]

        begin
          yield
        ensure
          req.stop_layer
          req.acknowledge_children! if options[:ignore_children]

        end
      end

      # Wraps a method in a call to #instrument via aggressive monkey patching.
      #
      # Options:
      # type - "View" or "ActiveRecord" and similar
      # name - "users/show", "App#find"
      def instrument_method(method, options = {})
        ScoutApm::Agent.instance.logger.info "Instrumenting #{method}"
        type = options[:type] || "Custom"
        name = options[:name] || "#{self.name}/#{method.to_s}"

        return if !instrumentable?(method) or instrumented?(method, type, name)

        class_eval(
          instrumented_method_string(method, type, name, {:scope => options[:scope] }),
          __FILE__, __LINE__
        )

        alias_method _uninstrumented_method_name(method, type, name), method
        alias_method method, _instrumented_method_name(method, type, name)
      end

      private

      def instrumented_method_string(method, type, name, options={})
        klass = (self === Module) ? "self" : "self.class"
        method_str = <<-EOF
        def #{_instrumented_method_name(method, type, name)}(*args, &block)
          #{klass}.instrument( "#{type}",
                               "#{name}",
                               {:scope => #{options[:scope] || false}}
                             ) do
            #{_uninstrumented_method_name(method, type, name)}(*args, &block)
          end
        end
        EOF

        method_str
      end

      # The method must exist to be instrumented.
      def instrumentable?(method)
        exists = method_defined?(method) || private_method_defined?(method)
        ScoutApm::Agent.instance.logger.warn "The method [#{self.name}##{method}] does not exist and will not be instrumented" unless exists
        exists
      end

      # +True+ if the method is already instrumented.
      def instrumented?(method, type, name)
        instrumented = method_defined?(_instrumented_method_name(method, type, name))
        ScoutApm::Agent.instance.logger.warn("The method [#{self.name}##{method}] has already been instrumented") if instrumented
        instrumented
      end

      # given a method and a metric, this method returns the
      # untraced alias of the method name
      def _uninstrumented_method_name(method, type, name)
        "#{_sanitize_name(method)}_without_scout_instrument_#{_sanitize_name(name)}"
      end

      # given a method and a metric, this method returns the traced
      # alias of the method name
      def _instrumented_method_name(method, type, name)
        "#{_sanitize_name(method)}_with_scout_instrument_#{_sanitize_name(name)}"
      end

      # Method names like +any?+ or +replace!+ contain a trailing character that would break when
      # eval'd as ? and ! aren't allowed inside method names.
      def _sanitize_name(name)
        name.to_s.tr_s('^a-zA-Z0-9', '_')
      end
    end
  end
end
