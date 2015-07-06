# Methods related to sending metrics to scoutapp.com.
module ScoutApm
  class Agent
    module Reporting
      # Called in the worker thread. Merges in-memory metrics w/those on disk and reports metrics
      # to the server.
      def process_metrics
        logger.debug "Processing metrics"
        run_samplers
        payload = layaway.deposit_and_deliver
        metrics = payload[:metrics]
        slow_transactions = payload[:slow_transactions]
        if payload.any?
          add_metric_ids(metrics)  
          logger.warn "Some data may be lost - metric size is at limit" if metrics.size == ScoutApm::Store::MAX_SIZE
          # for debugging, count the total number of requests    
          controller_count = 0
          metrics.each do |meta,stats|
            if meta.metric_name =~ /\AController/
              controller_count += stats.call_count
            end
          end      
          payload = Marshal.dump(:metrics => metrics, :slow_transactions => slow_transactions)
          slow_transactions_kb = Marshal.dump(slow_transactions).size/1024 # just for performance debugging
          logger.debug "#{config.settings['name']} Delivering total payload [#{payload.size/1024} KB] for #{controller_count} requests and slow transactions [#{slow_transactions_kb} KB] for #{slow_transactions.size} transactions of durations: #{slow_transactions.map(&:total_call_time).join(',')}."        
          response =  post( checkin_uri,
                             payload,
                             "Content-Type"     => "application/octet-stream" )
          if response and response.is_a?(Net::HTTPSuccess)
            directives = Marshal.load(response.body)
            self.metric_lookup.merge!(directives[:metric_lookup])
            if directives[:reset]
              logger.info "Resetting metric_lookup."
              self.metric_lookup = Hash.new
            end
            logger.debug "Metric Cache Size: #{metric_lookup.size}"
          end
        end
      rescue
        logger.info "Error on checkin to #{checkin_uri.to_s}"
        logger.info $!.message
        logger.debug $!.backtrace
      end
      
      # Before reporting, lookup metric_id for each MetricMeta. This speeds up 
      # reporting on the server-side.
      def add_metric_ids(metrics)
        metrics.each do |meta,stats|
          if metric_id = metric_lookup[meta]
            meta.metric_id = metric_id
          end
        end
      end
      
      def checkin_uri
        URI.parse("http://#{config.settings['host']}/apps/checkin.scout?key=#{config.settings['key']}&name=#{CGI.escape(config.settings['name'])}")
      end

      def post(url, body, headers = Hash.new)
        response = nil
        request(url) do |connection|
          post = Net::HTTP::Post.new( url.path +
                                      (url.query ? ('?' + url.query) : ''),
                                      HTTP_HEADERS.merge(headers) )
          post.body = body
          response=connection.request(post)
        end
        response
      end

      def request(url, &connector)
        response           = nil
        response           = http(url).start(&connector)
        logger.debug "got response: #{response.inspect}"
        case response
        when Net::HTTPSuccess, Net::HTTPNotModified
          logger.debug "/checkin OK"
        when Net::HTTPBadRequest
          logger.warn "/checkin FAILED: The Account Key [#{config.settings['key']}] is invalid."
        else
          logger.debug "/checkin FAILED: #{response.inspect}"
        end
      rescue Exception
        logger.debug "Exception sending request to server: #{$!.message}\n#{$!.backtrace}"
      ensure
        response
      end

      # Take care of the http proxy, if specified in config.
      # Given a blank string, the proxy_uri URI instance's host/port/user/pass will be nil.
      # Net::HTTP::Proxy returns a regular Net::HTTP class if the first argument (host) is nil.
      def http(url)
        proxy_uri = URI.parse(config.settings['proxy'].to_s)
        Net::HTTP::Proxy(proxy_uri.host,proxy_uri.port,proxy_uri.user,proxy_uri.password).new(url.host, url.port)
      end
    end # module Reporting
    include Reporting
  end # class Agent
end # module ScoutApm