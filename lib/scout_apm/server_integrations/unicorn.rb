module ScoutApm
  module ServerIntegrations
    class Unicorn
      attr_reader :logger

      def initialize(logger)
        @logger = logger
      end

      def name
        :unicorn
      end

      def forking?
        return true unless (defined?(::Unicorn) && defined?(::Unicorn::Configurator))
        ObjectSpace.each_object(::Unicorn::Configurator).first[:preload_app].tap {|x|
          logger.info "Unicorn is forking? #{x}"
        }
      rescue
        true
      end

      def present?
        if defined?(::Unicorn) && defined?(::Unicorn::HttpServer)
          # Ensure Unicorn is actually initialized. It could just be required and not running.
          ObjectSpace.each_object(::Unicorn::HttpServer) { |x| return true }
          false
        end
      end

      def install
        ::Unicorn::HttpServer.class_eval do
          old = instance_method(:worker_loop)
          define_method(:worker_loop) do |worker|
            ScoutApm::Agent.instance.start_background_worker
            old.bind(self).call(worker)
          end
        end
      end

      def found?
        true
      end
    end
  end
end

