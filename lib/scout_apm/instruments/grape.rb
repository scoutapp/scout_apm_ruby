module ScoutApm
  module Instruments
    class Grape
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

        if defined?(::Grape) && defined?(::Grape::Endpoint)
          ScoutApm::Agent.instance.logger.info "Instrumenting Grape::Endpoint"

          ::Grape::Endpoint.class_eval do
            include ScoutApm::Instruments::GrapeEndpointInstruments

            alias run_without_scout_instruments run
            alias run run_with_scout_instruments
          end
        end
      end
    end

    module GrapeEndpointInstruments
      def run_with_scout_instruments
        request = ::Grape::Request.new(env)
        req = ScoutApm::RequestManager.lookup
        path = ScoutApm::Agent.instance.config.value("uri_reporting") == 'path' ? request.path : request.fullpath
        req.annotate_request(:uri => path)

        # IP Spoofing Protection can throw an exception, just move on w/o remote ip
        req.context.add_user(:ip => request.ip) rescue nil

        req.set_headers(request.headers)
        req.web!

        action = self.options[:path].first

        # Get /api/v2/users from /api/v2/users/signin
        controller_path = path.gsub(/#{action}\z/, '')

        # Include method to distinguish between PUT /user and GET /user

        action = action[1..-1]
        method = self.options[:method].first.downcase
        if action.blank?
          action = method
        else
          action += "(#{method})"
        end

        req.start_layer( ScoutApm::Layer.new("Controller", "#{controller_path}/#{action}") )
        begin
          run_without_scout_instruments
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

