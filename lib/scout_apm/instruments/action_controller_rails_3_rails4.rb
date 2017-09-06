module ScoutApm
  module Instruments
    # instrumentation for Rails 3, 4, and 5 is the same.
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
        if defined?(::ActionController)
          if defined?(::ActionController::Base)
            ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Base"
            ::ActionController::Base.class_eval do
              # include ScoutApm::Tracer
              include ScoutApm::Instruments::ActionControllerBaseInstruments
            end
          end

          if defined?(::ActionController::Metal)
            ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Metal"
            ::ActionController::Metal.class_eval do
              include ScoutApm::Instruments::ActionControllerMetalInstruments
            end
          end

          if defined?(::ActionController::API)
            ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Api"
            ::ActionController::API.class_eval do
              include ScoutApm::Instruments::ActionControllerAPIInstruments
            end
          end
        end

      end

      # Returns a new anonymous module each time it is called. So
      # we can insert this multiple times into the ancestors
      # stack. Otherwise it only exists the first time you include it
      # (under Metal, instead of under API) and we miss instrumenting
      # before_action callbacks
      def self.build_instrument_module
        Module.new do
          def process_action(*args)
            req = ScoutApm::RequestManager.lookup
            current_layer = req.current_layer

            # Check if this this request is to be reported instantly
            if instant_key = request.cookies['scoutapminstant']
              Agent.instance.logger.info "Instant trace request with key=#{instant_key} for path=#{path}"
              req.instant_key = instant_key
            end

            if current_layer && current_layer.type == "Controller"
              # Don't start a new layer if ActionController::API or ActionController::Base handled it already.
              super
            else
              req.annotate_request(:uri => ScoutApm::Instruments::ActionControllerRails3Rails4.scout_transaction_uri(request))

              # IP Spoofing Protection can throw an exception, just move on w/o remote ip
              req.context.add_user(:ip => request.remote_ip) rescue nil
              req.set_headers(request.headers)

              req.web!

              resolved_name = scout_action_name(*args)
              layer = ScoutApm::Layer.new("Controller", "#{controller_path}/#{resolved_name}")

              if enable_scoutprof? && ScoutApm::Agent.instance.config.value('profile') && ScoutApm::Instruments::Stacks::ENABLED
                if defined?(ScoutApm::Instruments::Stacks::INSTALLED) && ScoutApm::Instruments::Stacks::INSTALLED
                  # Capture ScoutProf if we can
                  req.enable_profiled_thread!
                  layer.set_root_class(self.class)
                  layer.traced!
                end
              end

              req.start_layer(layer)
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

      # Given an +ActionDispatch::Request+, formats the uri based on config settings.
      def self.scout_transaction_uri(request)
        case ScoutApm::Agent.instance.config.value("uri_reporting")
        when 'path'
          request.path # strips off the query string for more security
        else # default handles filtered params
          request.filtered_path
        end
      end
    end

    module ActionControllerBaseInstruments
      include ScoutApm::Instruments::ActionControllerRails3Rails4.build_instrument_module

      def scout_action_name(*args)
        action_name
      end

      def enable_scoutprof?
        true
      end
    end

    module ActionControllerMetalInstruments
      include ScoutApm::Instruments::ActionControllerRails3Rails4.build_instrument_module

      def scout_action_name(*args)
        action_name = args[0]
      end

      def enable_scoutprof?
        false
      end
    end

    module ActionControllerAPIInstruments
      include ScoutApm::Instruments::ActionControllerRails3Rails4.build_instrument_module

      def scout_action_name(*args)
        action_name
      end

      def enable_scoutprof?
        false
      end
    end

    # Empty, noop module to provide compatibility w/ previous manual instrumentation
    module ActionControllerRails3Rails4Instruments
    end
  end
end

