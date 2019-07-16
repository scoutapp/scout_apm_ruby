module ScoutApm
  module Extensions
    class HostedGraphite
      def self.install
        ScoutApm::Extensions::Config.add_periodic_callback(self.new)
      end

      def initialize
        @socket = UDPSocket.new
      end

      def call(agent_context, reporting_period, metadata)
        @agent_context = agent_context

        reporting_period.metrics_payload.each do |meta, stat|
          @metric_name = meta.metric_name

          case metric_type
          when 'web'
            send("web.total_call_time", stat.total_call_time)
            send("web.throughput", stat.call_count)
          end
        end
      end

      private
      def send(metric_path, value)
        message = "#{prefix}#{metric_path}#{tags} #{value}"
        logger.debug "Sending #{message} to carbon.hostedgraphite.com"
        @socket.send "#{message}\n", 0, "carbon.hostedgraphite.com", 2003
      end

      def prefix
        "#{ENV['HOSTED_GRAPHITE_API_KEY']}.scout.#{app_name}."
      end

      def hostname
        @agent_context.environment.hostname.gsub(/\./, '_')
      end

      def app_name
        @agent_context.config.value('name').gsub(/\./, '_')
      end

      def metric_type
        case @metric_name
        when 'Memory/Physical'
          'memory'
        when 'CPU/Utilization'
          'cpu'
        when /^Controller\//
          'web'
        end
      end

      def tags
        ";hostname=#{hostname}" +
        case metric_type
        when 'web'
          ";endpoint=#{endpoint}"
        end
      end

      # tag can't include slash
      def endpoint
        @metric_name.gsub(/\//, '_')
      end

      def logger
        @agent_context.logger
      end
    end
  end
end
