module ScoutApm
  module Extensions
    class HostedGraphite
      def self.install
        ScoutApm::Extensions::Config.add_periodic_callback(self.new)
      end

      def initialize
        @socket = UDPSocket.new
        @agent_context = ScoutApm::Agent.instance.context
      end

      def call(reporting_period, metadata)
        reporting_period.metrics_payload.each do |meta, stat|

          case metric_type(meta.metric_name)
          when 'web'
            send("web.total_call_time", tags(meta.metric_name), stat.total_call_time)
            send("web.throughput", tags(meta.metric_name), stat.call_count)
          end
        end
      end

      private
      def send(metric_path, tags, value)
        message = "#{prefix}#{metric_path}#{tags} #{value}"
        logger.debug "Sending #{message} to carbon.hostedgraphite.com"
        @socket.send "#{message}\n", 0, "carbon.hostedgraphite.com", 2003
      end

      def prefix
        "#{ENV['HOSTED_GRAPHITE_API_KEY']}.scout.#{app_name}."
      end

      def hostname
        sanitize_for_graphite(@agent_context.environment.hostname)
      end

      def app_name
        sanitize_for_graphite(@agent_context.config.value('name'))
      end

      def metric_type(metric_name)
        case metric_name
        when 'Memory/Physical'
          'memory'
        when 'CPU/Utilization'
          'cpu'
        when /^Controller\//
          'web'
        end
      end

      def tags(metric_name)
        ";hostname=#{hostname}" +
        case metric_type(metric_name)
        when 'web'
          ";endpoint=#{endpoint(metric_name)}"
        end
      end

      # tag can't include slash
      def endpoint(metric_name)
        sanitize_for_graphite(metric_name)
      end

      def sanitize_for_graphite(string)
        string.gsub(/\.|\//, '_')
      end

      def logger
        @agent_context.logger
      end
    end
  end
end
