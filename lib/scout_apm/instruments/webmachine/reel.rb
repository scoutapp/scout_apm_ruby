module ScoutApm
  module Instruments
    module Webmachine
      class Reel
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

        # TODO: as configuration of webmachine arrive after install,
        # need to figure out how to detect if reel need to install
        def install
          if defined?(::Webmachine) && defined?(::Webmachine::Resource)
            @installed = true

            logger.info "Instrumenting Webmachine::Reel"

            ::Webmachine::Adapters::Reel.class_eval do
              include ScoutApm::Instruments::Webmachine::ReelInstruments

              alias process_without_scout_instruments process
              alias process process_with_scout_instruments
            end
          end
        end
      end

      module ReelInstruments
        def process_with_scout_instruments(connection)
          connection.each_request do |request|
            # Users of the adapter can configure a custom WebSocket handler
            if request.websocket?
              if handler = @options[:websocket_handler]
                handler.call(request.websocket)
              else
                # Pretend we don't know anything about the WebSocket protocol
                # FIXME: This isn't strictly what RFC 6455 would have us do
                request.respond :bad_request, "WebSockets not supported"
              end

              next
            end

            # Optional support for e.g. WebDAV verbs not included in Webmachine's
            # state machine. Do the "Railsy" thing and handle them like POSTs
            # with a magical parameter
            if @extra_verbs.include?(request.method)
              method = POST_METHOD
              param  = "_method=#{request.method}"
              uri    = request_uri(request.url, request.headers, param)
            else
              method = request.method
              uri    = request_uri(request.url, request.headers)
            end

            wm_headers = ::Webmachine::Headers[request.headers.dup]
            wm_headers['X-Request-Start'] = "t=#{Time.now.to_f}"
            wm_request = ::Webmachine::Request.new(method, uri, wm_headers, request.body)

            #+++++++++++++++++++++++++++
            req = ScoutApm::RequestManager.lookup

            # remove / from /my_resource
            path = wm_request.uri.path[1..-1]
            req.annotate_request(:uri => path)

            # IP Spoofing Protection can throw an exception, just move on w/o remote ip
            req.context.add_user(:ip => @options[:host]) rescue nil

            req.set_headers(wm_headers)

            begin
              name = ["Webmachine",
                      method,
                      path,
                      'to_json'
              ].compact.map{ |n| n.to_s }.join("/")
            rescue => e
              logger.info("Error getting Webmachine Reel Name. Error: #{e.message}. Options: #{self.options.inspect}")
              name = "Webmachine/Unknown"
            end

            req.start_layer( ScoutApm::Layer.new("Controller", name) )
            #----------------------------

            wm_response = ::Webmachine::Response.new
            application.dispatcher.dispatch(wm_request, wm_response)

            fixup_headers(wm_response)
            fixup_callable_encoder(wm_response)

            #+++++++++++++++++++++++++++
            begin
              request.respond ::Reel::Response.new(wm_response.code,
                                                   wm_response.headers,
                                                   wm_response.body)
            rescue
              req.error!
              raise
            ensure
              req.stop_layer
            end
            #-------------
          end
        end
      end
    end
  end
end
