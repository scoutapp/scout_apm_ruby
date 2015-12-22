module ScoutApm
  module Instruments
    class ActionControllerRails3
      attr_reader :logger

      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        # ActionController::Base is a subclass of ActionController::Metal, so this instruments both
        # standard Rails requests + Metal.
        if defined?(::ActionController) && defined?(::ActionController::Metal)
          ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Metal"
          ::ActionController::Metal.class_eval do
            # include ScoutApm::Tracer
            include ScoutApm::Instruments::ActionControllerRails3Instruments
          end
        end

        if defined?(::ActionView) && defined?(::ActionView::PartialRenderer)
          ScoutApm::Agent.instance.logger.info "Instrumenting ActionView::PartialRenderer"
          ::ActionView::PartialRenderer.class_eval do
            include ScoutApm::Tracer

            instrument_method :render_partial,
              :type => "View",
              :name => '#{@template.virtual_path rescue "Unknown Partial"}/Rendering',
              :scope => true

            instrument_method :collection_with_template,
              :type => "View",
              :name => '#{@template.virtual_path rescue "Unknown Collection"}/Rendering',
              :scope => true
          end

          ScoutApm::Agent.instance.logger.info "Instrumenting ActionView::TemplateRenderer"
          ::ActionView::TemplateRenderer.class_eval do
            include ScoutApm::Tracer
            instrument_method :render_template,
              :type => "View",
              :name => '#{args[0].virtual_path rescue "Unknown"}/Rendering',
              :scope => true
          end
        end
      end
    end

    module ActionControllerRails3Instruments
      def process_action(*args)
        req = ScoutApm::RequestManager.lookup
        req.annotate_request(:uri => request.fullpath)
        req.context.add_user(:ip => request.remote_ip)
        req.set_headers(request.headers)

        req.start_layer( ScoutApm::Layer.new("Controller", "#{controller_path}/#{action_name}") )
        begin
          super
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end
    end
  end
end

