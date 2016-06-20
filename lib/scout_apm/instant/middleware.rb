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

    class Middleware
      # def initialize(app)
      #   @app = app
      # end
      #
      # def call(env)
      # end

      def initialize(*args)
        @args = args
      end

      def call(env)
        "#{self.class}::Logic".constantize.new(*@args).call(env)
      end

      class Logic
        # When development is done, just replace the middleware classes' methods with these
        def initialize(app)
          @app        = app
        end

        def call(env)
          status, headers, response = @app.call(env)

          # Note that this middleware never even gets inserted unless Rails environment is development
          if ScoutApm::Agent.instance.config.value('instant')
            if response.respond_to?(:body)
              req = ScoutApm::RequestManager.lookup
              slow_converter = LayerConverters::SlowRequestConverter.new(req)
              trace = slow_converter.call
              if trace
                hash = ScoutApm::Serializers::PayloadSerializerToJson.rearrange_slow_transaction(trace)
                hash.merge!(id:env['action_dispatch.request_id']) # TODO: this could be separated into a metadata section
                payload = ScoutApm::Serializers::PayloadSerializerToJson.jsonify_hash(hash)


                if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
                  # Add the payload as a header if it's an AJAX call
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
                    # preserve the ActionDispatch::Response when applicable
                    response.body=[page.res]
                    [status, headers, response]
                  else
                    # otherwise, just return an array
                    # TODO: this will break ActionCable repsponse
                    [status, headers, [page.res]]
                  end
                end
              else
                [status, headers, response]
              end
            else
              [status, headers, response]
            end
          else
            [status, headers, response]
          end
        end
      end
    end
  end
end