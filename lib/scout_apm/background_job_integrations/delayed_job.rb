module ScoutApm
  module BackgroundJobIntegrations
    class DelayedJob
      attr_reader :logger

      def name
        :delayed_job
      end

      def present?
        defined?(::Delayed::Job) && (File.basename($0) =~ /\Adelayed_job/)
      end
    end
  end
end
