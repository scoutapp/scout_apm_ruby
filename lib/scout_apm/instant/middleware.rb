module ScoutApm
  module Instant

    # an abstraction for manipulating the HTML we capture in the middleware
    class Page
      def initialize(html)
        @html = html
        @to_add_to_head = []
        @to_add_to_body = []
      end

      def add_to_head(content)
        @to_add_to_head << content
      end

      def add_to_body(content)
        @to_add_to_body << content
      end

      def res
        i = @html.index("</body>")
        @html = @html.insert(i, @to_add_to_body.join("")) if i
        i = @html.index("</head>")
        @html = @html.insert(i, @to_add_to_head.join("")) if i
        @html
      end
    end

    class Util
      # reads the literal contents of the file in assets/#{name}
      # if any vars are supplied, do a simple string substitution of the vars for their values
      def self.read_asset(name, vars = {})
        contents = File.read(File.join(File.dirname(__FILE__), "assets", name))
        if vars.any?
          vars.each_pair{|k,v| contents.gsub!(k.to_s,v.to_s)}
        end
        contents
      end
    end

    # Note that this middleware never even gets inserted unless Rails environment is development (See Railtie)
    class Middleware
      def initialize(app)
        ScoutApm::Agent.instance.logger.info("Activating Scout DevTrace because environment=development and dev_trace=true in scout_apm config")
        @app        = app
      end

      def call(env)
        status, headers, response = @app.call(env)
        path, content_type = env['PATH_INFO'], headers['Content-Type']
        if ScoutApm::Agent.instance.config.value('dev_trace')
          if response.respond_to?(:body)
            req = ScoutApm::RequestManager.lookup
            slow_converter = LayerConverters::SlowRequestConverter.new(req)
            trace = slow_converter.call
            if trace
              metadata = {
                  :app_root      => ScoutApm::Environment.instance.root.to_s,
                  :unique_id     => env['action_dispatch.request_id'], # note, this is a different unique_id than what "normal" payloads use
                  :agent_version => ScoutApm::VERSION,
                  :platform      => "ruby",
              }
              hash = ScoutApm::Serializers::PayloadSerializerToJson.rearrange_slow_transaction(trace)
              hash.merge!(metadata:metadata)
              payload = ScoutApm::Serializers::PayloadSerializerToJson.jsonify_hash(hash)

              if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest' || content_type.include?("application/json")
                ScoutApm::Agent.instance.logger.debug("DevTrace: in middleware, dev_trace is active, and response has a body. This is either AJAX or JSON. Path=#{path}; ContentType=#{content_type}")
                # Add the payload as a header if it's an AJAX call or JSON
                headers['X-scoutapminstant'] = payload
                [status, headers, response]
              else
                # otherwise, attempt to add it inline in the page, along with the appropriate JS & CSS. Note, if page doesn't have a head or body,
                #duration = (req.root_layer.total_call_time*1000).to_i
                apm_host=ScoutApm::Agent.instance.config.value("direct_host")
                page = ScoutApm::Instant::Page.new(response.body)
                page.add_to_head(ScoutApm::Instant::Util.read_asset("xmlhttp_instrumentation.html")) # This monkey-patches XMLHttpRequest. It could possibly be part of the main scout_instant.js too. Putting it here so it runs as soon as possible.
                page.add_to_head("<link href='#{apm_host}/instant/scout_instant.css?cachebust=#{Time.now.to_i}' media='all' rel='stylesheet' />")
                page.add_to_body("<script src='#{apm_host}/instant/scout_instant.js?cachebust=#{Time.now.to_i}'></script>")
                page.add_to_body("<script>var scoutInstantPageTrace=#{payload};window.scoutInstant=window.scoutInstant('#{apm_host}', scoutInstantPageTrace)</script>")

                if response.is_a?(ActionDispatch::Response)
                  ScoutApm::Agent.instance.logger.debug("DevTrace: in middleware, dev_trace is active, and response has a body. This appears to be an HTML page and an ActionDispatch::Response. Path=#{path}; ContentType=#{content_type}")
                  # preserve the ActionDispatch::Response when applicable
                  response.body=[page.res]
                  [status, headers, response]
                else
                  ScoutApm::Agent.instance.logger.debug("DevTrace: in middleware, dev_trace is active, and response has a body. This appears to be an HTML page but not an ActionDispatch::Response. Path=#{path}; ContentType=#{content_type}")
                  # otherwise, just return an array
                  [status, headers, [page.res]]
                end
              end
            else
              ScoutApm::Agent.instance.logger.debug("DevTrace: in middleware, dev_trace is active, and response has a body, but no trace was found. Path=#{path}; ContentType=#{content_type}")
              [status, headers, response]
            end
          else
            # don't log anything here - this is the path for all assets served in development, and the log would get noisy
            [status, headers, response]
          end
        else
          ScoutApm::Agent.instance.logger.debug("DevTrace: isn't activated via config. Try: SCOUT_DEV_TRACE=true rails server")
          [status, headers, response]
        end
      end
    end
  end
end