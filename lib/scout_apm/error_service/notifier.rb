module ScoutApm
  module ErrorService
    class Notifier
      class << self
        def notify(data)
          @data = data
          serialized_data = {problem: data}.to_json
          send_problem(serialized_data) unless ignore_exception?
        end

        def send_problem(serialized_data)
          url = URI.parse((Config.use_ssl? ? "https://" : "http://") << Config.notification_url)
          client = prepare_client(url)

          headers = HEADERS
          headers["X-Api-Key"] = Config.api_key

          response =
            begin
              client.post(url.path, serialized_data, headers)
            rescue TimeoutError => e
              ScoutApm::Agent.instance.logger.info("ERROR: Timeout while contacting Scout Error Service.")
              nil
            rescue Exception => e
              ScoutApm::Agent.instance.logger.info("ERROR: Error on sending to Scout Error Service: #{e.class} - #{e.message}")
            end
        end

        private

        def ignore_exception?
          Config.ignored_exceptions.include?(@data["name"])
        end

        def prepare_client(url)
          if Config.use_ssl?
            client = Net::HTTP.new(url.host, url.port || 443)
            client.use_ssl = true
            client.verify_mode = OpenSSL::SSL::VERIFY_NONE
          else
            client = Net::HTTP.new(url.host, url.port || 80)
          end

          client
        end
      end
    end
  end
end
