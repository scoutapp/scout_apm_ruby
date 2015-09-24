module ScoutApm
  module Instruments
    class Sinatra
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

        if defined?(::Sinatra) && defined?(::Sinatra::Base) && ::Sinatra::Base.private_method_defined?(:dispatch!)
          ScoutApm::Agent.instance.logger.debug "Instrumenting Sinatra"
          ::Sinatra::Base.class_eval do
            include ScoutApm::Tracer
            include ScoutApm::Instruments::SinatraInstruments
            alias dispatch_without_scout_instruments! dispatch!
            alias dispatch! dispatch_with_scout_instruments!
          end
        end
      end
    end

    module SinatraInstruments
      def dispatch_with_scout_instruments!
        scout_controller_action = "Controller/Sinatra/#{scout_sinatra_controller_name(@request)}"
        self.class.scout_apm_trace(scout_controller_action, :uri => @request.path_info, :ip => @request.ip) do
          dispatch_without_scout_instruments!
        end
      end

      # Iterates through the app's routes, returning the matched route that the request should be 
      # grouped under for the metric name. 
      #
      # If not found, "unknown" is returned. This prevents a metric explosion.
      #
      # Nice to have: substitute the param pattern (([^/?#]+)) w/the named key (the +key+ param of the block).
      def scout_sinatra_controller_name(request)
        name = 'unknown'
        verb = request.request_method if request && request.respond_to?(:request_method) 
        Array(self.class.routes[verb]).each do |pattern, keys, conditions, block|
          if pattern = process_route(pattern, keys, conditions) { pattern.source }
            name = pattern
          end
        end
        name.gsub!(%r{^[/^]*(.*?)[/\$\?]*$}, '\1')
        if verb
          name = [verb,name].join(' ')
        end
        name
      end
    end
  end
end

