module ScoutApm
  module Instruments
    class Grape
      attr_reader :context

      def initialize(context)
        @context = context
        @installed = false
      end

      def logger
        context.logger
      end

      def installed?
        @installed
      end

      def install(prepend:)
        if defined?(::Grape) && defined?(::Grape::Endpoint)
          @installed = true

          # Grape >= 3.3.0 prepends a module of its own (Grape::Testing::RunBeforeEach)
          # in front of Grape::Endpoint#run. An alias-method chain built on a method
          # owned by a prepended module recurses infinitely (SystemStackError), because
          # the aliased copy's `super` resolves back into our wrapper. Whenever #run is
          # not owned by Grape::Endpoint itself, prepend is the only safe option.
          prepend = true unless endpoint_owns_run?

          logger.info "Instrumenting Grape::Endpoint. Prepend: #{prepend}"

          if prepend
            ::Grape::Endpoint.send(:prepend, GrapeEndpointInstrumentsPrepend)
          else
            ::Grape::Endpoint.class_eval do
              include ScoutApm::Instruments::GrapeEndpointInstruments

              alias run_without_scout_instruments run
              alias run run_with_scout_instruments
            end
          end
        end
      end

      private

      def endpoint_owns_run?
        ::Grape::Endpoint.instance_method(:run).owner == ::Grape::Endpoint
      rescue NameError
        true
      end
    end

    module GrapeEndpointNaming
      # Grape >= 4 moved endpoint route metadata off the public `options`
      # Hash and onto `Endpoint#config` (a Grape::Endpoint::Options Data
      # object). Support both so the instrument works across Grape 3 and 4.
      def self.name_for(endpoint)
        # `config` is a protected reader on Grape::Endpoint, so a public
        # respond_to? misses it: check with `true` and read via `send`.
        if endpoint.respond_to?(:config, true) && endpoint.send(:config).respond_to?(:http_methods)
          config = endpoint.send(:config)
          method = config.http_methods && config.http_methods.first
          api = config.api || (endpoint.respond_to?(:api) ? endpoint.api : nil)
          path = config.path && config.path.first
        else
          method = endpoint.options[:method] && endpoint.options[:method].first
          api = endpoint.options[:for]
          path = endpoint.options[:path] && endpoint.options[:path].first
        end

        ["Grape",
         method,
         api.to_s,
         endpoint.namespace.sub(%r{\A/}, ''), # removing leading slashes
         path,
        ].compact.map { |n| n.to_s }.join("/")
      rescue => e
        ScoutApm::Agent.instance.context.logger.info("Error getting Grape Endpoint Name. Error: #{e.message}. Options: #{endpoint.options.inspect}")
        "Grape/Unknown"
      end
    end

    module GrapeEndpointInstruments
      def run_with_scout_instruments(*args)
        request = ::Grape::Request.new(env || args.first)
        req = ScoutApm::RequestManager.lookup

        path = ScoutApm::Agent.instance.context.config.value("uri_reporting") == 'path' ? request.path : request.fullpath
        req.annotate_request(:uri => path)

        # IP Spoofing Protection can throw an exception, just move on w/o remote ip
        req.context.add_user(:ip => request.ip) rescue nil

        req.set_headers(request.headers)

        name = GrapeEndpointNaming.name_for(self)

        req.start_layer( ScoutApm::Layer.new("Controller", name) )
        begin
          run_without_scout_instruments(*args)
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end
    end

    module GrapeEndpointInstrumentsPrepend
      def run(*args)
        request = ::Grape::Request.new(env || args.first)
        req = ScoutApm::RequestManager.lookup

        path = ScoutApm::Agent.instance.context.config.value("uri_reporting") == 'path' ? request.path : request.fullpath
        req.annotate_request(:uri => path)

        # IP Spoofing Protection can throw an exception, just move on w/o remote ip
        req.context.add_user(:ip => request.ip) rescue nil

        req.set_headers(request.headers)

        name = GrapeEndpointNaming.name_for(self)

        req.start_layer( ScoutApm::Layer.new("Controller", name) )
        begin
          super(*args)
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end
    end
  end
end
