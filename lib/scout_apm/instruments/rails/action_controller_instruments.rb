module ScoutApm::Instruments
  module ActionControllerInstruments
    def self.included(instrumented_class)
      ScoutApm::Agent.instance.logger.debug "Instrumenting #{instrumented_class.inspect}"
      instrumented_class.class_eval do
        unless instrumented_class.method_defined?(:perform_action_without_scout_instruments)
          alias_method :perform_action_without_scout_instruments, :perform_action
          alias_method :perform_action, :perform_action_with_scout_instruments
          private :perform_action
        end
      end
    end # self.included

    # In addition to instrumenting actions, this also sets the scope to the controller action name. The scope is later
    # applied to metrics recorded during this transaction. This lets us associate ActiveRecord calls with
    # specific controller actions.
    def perform_action_with_scout_instruments(*args, &block)
      scout_controller_action = "Controller/#{controller_path}/#{action_name}"
      self.class.scout_apm_trace(scout_controller_action, :uri => request.request_uri, :ip => request.remote_ip) do
        perform_action_without_scout_instruments(*args, &block)
      end
    end
  end
end

if defined?(ActionController) && defined?(ActionController::Base)
  ActionController::Base.class_eval do
    include ScoutApm::Tracer
    include ::ScoutApm::Instruments::ActionControllerInstruments

    def rescue_action_with_scout(exception)
      ScoutApm::Agent.instance.store.track!("Errors/Request",1, :scope => nil)
      ScoutApm::Agent.instance.store.ignore_transaction!
      rescue_action_without_scout exception
    end

    alias_method :rescue_action_without_scout, :rescue_action
    alias_method :rescue_action, :rescue_action_with_scout
    protected :rescue_action
  end
  ScoutApm::Agent.instance.logger.debug "Instrumenting ActionView::Template"
  ActionView::Template.class_eval do
    include ::ScoutApm::Tracer
    instrument_method :render, :metric_name => 'View/#{path[%r{^(/.*/)?(.*)$},2]}/Rendering', :scope => true
  end
end
