module ScoutApm
  module ServerIntegrations
    class Puma
      def name
        :puma
      end

      def forking?; true; end

      def present?
        defined?(::Puma) && File.basename($0) == 'puma'
      end

      def install
        Puma.cli_config.options[:before_worker_boot] << Proc.new do
          logger.debug "Installing Puma worker loop."
          ScoutApm::Agent.instance.start_background_worker
        end
      rescue
        logger.warn "Unable to install Puma worker loop: #{$!.message}"
      end
    end
  end
end
