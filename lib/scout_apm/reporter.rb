module ScoutApm
  class Reporter
    CA_FILE     = File.join( File.dirname(__FILE__), *%w[.. .. data cacert.pem] )
    VERIFY_MODE = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

    attr_reader :config
    attr_reader :logger

    def initialize(config, logger=NullLogger.new)
      @config = config
      @logger = logger
    end

    # TODO: Parse & return a real response object, not the HTTP Response object
    def report(payload)
      post(checkin_uri, payload)
    end

    def checkin_uri
      URI.parse("#{config.value('host')}/apps/checkin.scout?key=#{config.value('key')}&name=#{CGI.escape(config.value('name'))}")
    end

    private

    def post(uri, body, headers = Hash.new)
      response = nil
      request(uri) do |connection|
        post = Net::HTTP::Post.new( uri.path +
                                    (uri.query ? ('?' + uri.query) : ''),
                                    default_http_headers.merge(headers) )
        post.body = body
        response=connection.request(post)
      end
      response
    end

    def request(uri, &connector)
      response           = nil
      response           = http(uri).start(&connector)
      logger.debug "got response: #{response.inspect}"
      case response
      when Net::HTTPSuccess, Net::HTTPNotModified
        logger.debug "/checkin OK"
      when Net::HTTPBadRequest
        logger.warn "/checkin FAILED: The Account Key [#{config.value('key')}] is invalid."
      else
        logger.debug "/checkin FAILED: #{response.inspect}"
      end
    rescue Exception
      logger.debug "Exception sending request to server: #{$!.message}\n#{$!.backtrace}"
    ensure
      response
    end

    # Headers passed up with all API requests.
    def default_http_headers
      { "Agent-Hostname" => ScoutApm::Environment.instance.hostname,
        "Content-Type"   => "application/octet-stream"
      }
    end

    # Take care of the http proxy, if specified in config.
    # Given a blank string, the proxy_uri URI instance's host/port/user/pass will be nil.
    # Net::HTTP::Proxy returns a regular Net::HTTP class if the first argument (host) is nil.
    def http(url)
      proxy_uri = URI.parse(config.value('proxy').to_s)
      http = Net::HTTP::Proxy(proxy_uri.host,proxy_uri.port,proxy_uri.user,proxy_uri.password).new(url.host, url.port)
      if url.is_a?(URI::HTTPS)
        http.use_ssl = true
        http.ca_file = CA_FILE
        http.verify_mode = VERIFY_MODE
      end
      http
    end
  end
end
