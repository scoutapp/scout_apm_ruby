require 'openssl'

module ScoutApm
  class Reporter
    CA_FILE     = File.join( File.dirname(__FILE__), *%w[.. .. data cacert.pem] )
    VERIFY_MODE = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

    attr_reader :config
    attr_reader :logger
    attr_reader :type
    attr_reader :instant_key

    def initialize(type = :checkin, config=Agent.instance.config, logger=Agent.instance.logger, instant_key=nil)
      @config = config
      @logger = logger
      @type = type
      @instant_key = instant_key
    end

    # TODO: Parse & return a real response object, not the HTTP Response object
    def report(payload, headers = {})
      # Some posts (typically ones under development) bypass the ingestion pipeline and go directly to the webserver. They use direct_host instead of host
      hosts = [:deploy_hook, :instant_trace].include?(type) ? config.value('direct_host') : config.value('host')

      Array(hosts).each do |host|
        full_uri = uri(host)
        response = post(full_uri, payload, headers)
        unless response && response.is_a?(Net::HTTPSuccess)
          logger.warn "Error on checkin to #{full_uri.to_s}: #{response.inspect}"
        end
      end
    end

    def uri(host)
      case type
      when :checkin
        URI.parse("#{host}/apps/checkin.scout?key=#{config.value('key')}&name=#{CGI.escape(Environment.instance.application_name)}")
      when :app_server_load
        URI.parse("#{host}/apps/app_server_load.scout?key=#{config.value('key')}&name=#{CGI.escape(Environment.instance.application_name)}")
      when :deploy_hook
        URI.parse("#{host}/apps/deploy.scout?key=#{config.value('key')}&name=#{CGI.escape(config.value('name'))}")
      when :instant_trace
        URI.parse("#{host}/apps/instant_trace.scout?key=#{config.value('key')}&name=#{CGI.escape(config.value('name'))}&instant_key=#{instant_key}")
      end.tap{|u| logger.debug("Posting to #{u.to_s}")}
    end

    def can_report?
      case type
      when :deploy_hook
        %w(host key name).each do |k|
          if config.value(k).nil?
            logger.warn "/#{type} FAILED: missing required config value for #{k}"
            return false
          end
        end
        return true
      else
        return true
      end
    end

    private

    def post(uri, body, headers = Hash.new)
      response = :connection_failed
      request(uri) do |connection|
        post = Net::HTTP::Post.new( uri.path +
                                    (uri.query ? ('?' + uri.query) : ''),
                                    default_http_headers.merge(headers) )
        post.body = body
        response = connection.request(post)
      end
      response
    end

    def request(uri, &connector)
      response           = nil
      response           = http(uri).start(&connector)
      logger.debug "got response: #{response.inspect}"
      case response
      when Net::HTTPSuccess, Net::HTTPNotModified
        logger.debug "/#{type} OK"
      when Net::HTTPBadRequest
        logger.warn "/#{type} FAILED: The Account Key [#{config.value('key')}] is invalid."
      when Net::HTTPUnprocessableEntity
        logger.warn "/#{type} FAILED: #{response.body}"
      else
        logger.debug "/#{type} FAILED: #{response.inspect}"
      end
    rescue Exception
      logger.info "Exception sending request to server: \n#{$!.message}\n\t#{$!.backtrace.join("\n\t")}"
    ensure
      response
    end

    # Headers passed up with all API requests.
    def default_http_headers
      { "Agent-Hostname" => ScoutApm::Environment.instance.hostname,
        "Content-Type"   => "application/octet-stream",
        "Agent-Version"  => ScoutApm::VERSION,
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
