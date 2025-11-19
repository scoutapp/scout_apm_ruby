module ScoutApm
  module Instruments
    class HTTPX
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
        if defined?(::HTTPX) && defined?(::HTTPX::Session)
          @installed = true

          logger.info "Instrumenting HTTPX"

          ::HTTPX::Session.send(:prepend, HTTPXInstrumentationPrepend)
        end
      end

      module HTTPXInstrumentationPrepend
        def request(*args, **params)
          verb, desc = determine_verb_and_desc(*args, **params)

          layer = ScoutApm::Layer.new("HTTP", verb)
          layer.desc = desc

          req = ScoutApm::RequestManager.lookup
          req.start_layer(layer)

          begin
            super(*args, **params)
          ensure
            req.stop_layer
          end
        end

        private

        # See the following for various argument patterns:
        # https://gitlab.com/os85/httpx/-/blob/v1.6.3/lib/httpx/session.rb?ref_type=tags#L87
        def determine_verb_and_desc(*args, **params)
          # Pattern 1: session.request(req1) or session.request(req1, req2, ...)
          if args.first.is_a?(::HTTPX::Request)
            if args.length > 1
              return args.first.verb.to_s.upcase, "#{args.length} requests"
            else
              return args.first.verb.to_s.upcase, scout_url_desc(args.first.uri)
            end
          end

          # Pattern 2: session.request("GET", "https://server.org/a")
          # Pattern 3: session.request("GET", ["https://server.org/a", "https://server.org/b"])
          # Pattern 4: session.request("POST", ["https://server.org/a"], form: { ... })
          # Pattern 5: session.request("GET", ["https://..."], headers: { ... })
          if args.first.is_a?(String) || args.first.is_a?(Symbol)
            verb = args.first.to_s.upcase

            if args[1].is_a?(String)
              return verb, scout_url_desc(args[1])
            elsif args[1].is_a?(Array)
              return verb, scout_url_desc(args[1][0]) unless args[1].length > 1
              return verb, "#{args[1].length} requests"
            else
              return verb, ""
            end
          end

          # Pattern 6: session.request(["GET", "https://..."], ["GET", "https://..."])
          # Pattern 7: session.request(["POST", "https://...", form: {...}], ["GET", "https://..."])
          if args.first.is_a?(Array)
            if args.length > 1
              verb = args.first[0].to_s.upcase rescue "REQUEST"
              return verb, "#{args.length} requests"
            elsif args.first.length >= 2
              verb = args.first[0].to_s.upcase rescue "REQUEST"
              url = args.first[1]
              return verb, scout_url_desc(url)
            end
          end

          return "REQUEST", ""
        end

        def scout_url_desc(uri)
          max_length = ScoutApm::Agent.instance.context.config.value('instrument_http_url_length')
          uri_str = uri.to_s

          # URI object
          if uri.respond_to?(:host) && uri.respond_to?(:path)
            path = uri.path.to_s
            path = "/" if path.empty?
            result = "#{uri.host}#{path.split('?').first}"
          # String URL
          elsif uri_str =~ %r{^https?://([^/]+)(/[^?]*)?}
            host = $1
            path = $2 || "/"
            result = "#{host}#{path}"
          else
            # Fallback
            result = uri_str.split('?').first
          end

          result[0..(max_length - 1)]
        rescue => e
          ""
        end
      end
    end
  end
end
