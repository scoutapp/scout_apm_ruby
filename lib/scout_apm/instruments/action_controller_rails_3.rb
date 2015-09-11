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
          ScoutApm::Agent.instance.logger.debug "Instrumenting ActionController::Metal"
          ::ActionController::Metal.class_eval do
            include ScoutApm::Tracer
            include ScoutApm::Instruments::ActionControllerRails3Instruments
          end
        end

        if defined?(::ActionView) && defined?(::ActionView::PartialRenderer)
          ScoutApm::Agent.instance.logger.debug "Instrumenting ActionView::PartialRenderer"
          ::ActionView::PartialRenderer.class_eval do
            include ScoutApm::Tracer
            instrument_method :render_partial,
              :metric_name => 'View/#{@template.virtual_path rescue "Unknown Partial"}/Rendering',
              :scope => true

            instrument_method :collection_with_template,
              :metric_name => 'View/#{@template.virtual_path rescue "Unknown Collection"}/Rendering',
              :scope => true
          end

          ScoutApm::Agent.instance.logger.debug "Instrumenting ActionView::TemplateRenderer"
          ::ActionView::TemplateRenderer.class_eval do
            include ScoutApm::Tracer
            instrument_method :render_template,
              :metric_name => 'View/#{args[0].virtual_path rescue "Unknown"}/Rendering',
              :scope => true
          end
        end
      end
    end

    module ActionControllerRails3Instruments
      # Instruments the action and tracks errors.
      def process_action(*args)
        scout_controller_action = "Controller/#{controller_path}/#{action_name}"

        self.class.scout_apm_trace(scout_controller_action, :uri => request.fullpath, :ip => request.remote_ip) do
          Thread::current[:scout_apm_prof] = nil
          if defined?(StackProf)
            STDOUT.puts("STARTING Stackprof")
            StackProf.start(mode: :wall, interval: 20000)
          end

          begin
            super
          rescue Exception
            ScoutApm::Agent.instance.store.track!("Errors/Request",1, :scope => nil)
            raise
          ensure
            Thread::current[:scout_apm_scope_name] = nil
            if defined?(StackProf)
              STDOUT.puts("STOPPING Stackprof")
              StackProf.stop
              Thread::current[:scout_apm_prof] = StackProf.results
            else
              Thread::current[:scout_apm_prof] = { "frames" => [] }
            end
          end
        end
      end
    end
  end
end

