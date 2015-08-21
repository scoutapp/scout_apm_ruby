module ScoutApm
  module ServerIntegrations
    class Unicorn
      def self.install
        logger.debug "Installing Unicorn worker loop."

        Unicorn::HttpServer.class_eval do
          old = instance_method(:worker_loop)
          define_method(:worker_loop) do |worker|
            ScoutApm::Agent.instance.start_background_worker
            old.bind(self).call(worker)
          end
        end
      end
    end
  end
end
