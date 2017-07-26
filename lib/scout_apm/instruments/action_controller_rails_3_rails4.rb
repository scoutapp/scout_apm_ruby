module ScoutApm
  module Instruments
    # instrumentation for Rails 3 and Rails 4 is the same.
    class ActionControllerRails3Rails4
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

        # We previously instrumented ActionController::Metal, which missed
        # before and after filter timing. Instrumenting Base includes those
        # filters, at the expense of missing out on controllers that don't use
        # the full Rails stack.
        if defined?(::ActionController) && defined?(::ActionController::Base)
          ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Base"
          ::ActionController::Base.class_eval do
            # include ScoutApm::Tracer
            include ScoutApm::Instruments::ActionControllerRails3Rails4Instruments
          end
          ScoutApm::Agent.instance.logger.info "Installing ScoutProf profiling" if ScoutApm::Agent.instance.config.value('profile')
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

    module ActionControllerRails3Rails4Instruments
      def process_action(*args)
        req = ScoutApm::RequestManager.lookup
        req.annotate_request(:uri => scout_transaction_uri(request))

        # IP Spoofing Protection can throw an exception, just move on w/o remote ip
        req.context.add_user(:ip => request.remote_ip) rescue nil

        req.set_headers(request.headers)

        # Check if this this request is to be reported instantly
        if instant_key = request.cookies['scoutapminstant']
          Agent.instance.logger.info "Instant trace request with key=#{instant_key} for path=#{path}"
          req.instant_key = instant_key
        end

        req.web!

        layer = ScoutApm::Layer.new("Controller", "#{controller_path}/#{action_name}")

        if ScoutApm::Agent.instance.config.value('profile')
          layer.set_root_class(self.class)
          layer.traced!
        end

        # Start the layer, then execute the user's code
        req.start_layer(layer)
        begin
          super
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end # process_action

      # Given an +ActionDispatch::Request+, formats the uri based on config settings.
      def scout_transaction_uri(request)
        case ScoutApm::Agent.instance.config.value("uri_reporting")
        when 'path'
          request.path # strips off the query string for more security
        else # default handles filtered params
          request.filtered_path
        end
      end

    end # ActionControllerRails3Rails4Instruments
  end
end

