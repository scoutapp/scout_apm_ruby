module ScoutApm
  module Extensions
    class HostedGraphite
      def self.install
        ScoutApm::Extensions::Config.add_periodic_callback(self)
      end

      def self.call(agent_context, reporting_period, metadata)
        @agent_context = agent_context

        reporting_period.metrics_payload.each do |meta, stat|
          case metric_type(meta.metric_name)
          when 'web'
            send('web.total_call_time', stat.total_call_time)
            send('web.throughput', stat.call_count)
          end
        end
      end

      private
      def self.send(metric_path, value)
        @@socket ||= UDPSocket.new
        @@socket.send "#{prefix}#{metric_path} #{value}\n", 0, "carbon.hostedgraphite.com", 2003
      end

      def self.prefix
        "#{ENV['HOSTED_GRAPHITE_API_KEY']}.scout."
      end

      def self.hostname
        @agent_context.environment.hostname.gsub(/\./, '_')
      end

      def self.app_name
        @agent_context.config.value('name').gsub(/\./, '_')
      end

      def self.metric_type(metric_name)
        case metric_name
        when 'Memory/Physical'
          'memory'
        when 'CPU/Utilization'
          'cpu'
        when /^Controller\//
          'web'
        end
      end
    end
  end
end