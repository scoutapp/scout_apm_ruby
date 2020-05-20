module ScoutApm
  module ErrorService
    class Data
      class << self
        def rack_data(exception, env = {})
          components = {}
          unless env["action_dispatch.request.parameters"].nil?
            components[:controller] = env["action_dispatch.request.parameters"][:controller] || nil
            components[:action] = env["action_dispatch.request.parameters"][:action] || nil
            components[:module] = env["action_dispatch.request.parameters"][:module] || nil
          end

          # For background workers like sidekiq # TODO: extract data creation for background jobs
          components[:controller] ||= env[:custom_controller]

          data = {
            "notifier" => NOTIFIER_NAME,
            "name" => exception.class.name,
            "message" => exception.message,
            "location" => location(exception),
            "root" => application_root.to_s,
            "app_environment" => application_environment,
            "request_uri" => rack_request_url(env),
            "request_params" => clean_params(env["action_dispatch.request.parameters"]),
            "request_session" => clean_params(session_data(env)),
            "environment" => clean_params(strip_env(env)),
            "trace" => clean_backtrace(exception.backtrace),
            "request_components" => components
          }
        end

        def rack_request_url(env)
          protocol = rack_scheme(env)
          protocol = protocol.nil? ? "" : "#{protocol}://"

          host = env["SERVER_NAME"] || ""
          path = env["REQUEST_URI"] || ""
          port = env["SERVER_PORT"] || "80"
          port = ["80", "443"].include?(port.to_s) ? "" : ":#{port}"

          protocol.to_s + host.to_s + port.to_s + path.to_s
        end

        def rack_scheme(env)
          if env["HTTPS"] == "on"
            "https"
          elsif env["HTTP_X_FORWARDED_PROTO"]
            env["HTTP_X_FORWARDED_PROTO"].split(",")[0]
          else
            env["rack.url_scheme"]
          end
        end

        # Cleanup data
        def clean_params(params)
          return if params.nil?
          params = normalize_data(params)
          params = filter_params(params)
        end

        def clean_backtrace(backtrace)
          if Rails.respond_to?(:backtrace_cleaner)
            Rails.backtrace_cleaner.send(:filter, backtrace)
          else
            backtrace
          end
        end

        # Deletes params from env / set in config file
        def strip_env(env)
          keys_to_remove = ["rack.request.form_hash", "rack.request.form_vars", "async.callback"]
          env.reject { |k, v| keys_to_remove.include?(k) }
        end

        # Replaces parameter values with a string / set in config file
        def filter_params(params)
          return params unless filtered_params_config

          params.each do |k, v|
            if filter_key?(k)
              params[k] = "[FILTERED]"
            elsif v.respond_to?(:to_hash)
              filter_params(params[k])
            end
          end

          params
        end

        # Check, if a key should be filtered
        def filter_key?(key)
          filtered_params_config.any? do |filter|
            key.to_s == filter.to_s # key.to_s.include?(filter.to_s)
          end
        end

        def session_data(env)
          session = env["action_dispatch.request.session"]
          return if session.nil?

          if session.respond_to?(:to_hash)
            session.to_hash
          else
            session.data
          end
        end

        def location(exception)
          # TODO: Implement
        end

        def application_environment
          ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "development"
        end

        def application_root
          defined?(Rails.root) ? Rails.root : Dir.pwd
        end

        # TODO: Refactor
        def normalize_data(hash)
          new_hash = {}

          hash.each do |key, value|
            if value.respond_to?(:to_hash)
              begin
                new_hash[key] = normalize_data(value.to_hash)
              rescue
                new_hash[key] = value.to_s
              end
            else
              new_hash[key] = value.to_s
            end
          end

          new_hash
        end

        # Accessor for the filtered params config value. Will be removed as we refactor and clean up this code.
        def filtered_params_config
          ScoutApm::Agent.instance.context.config.value("errors_filtered_params")
        end
      end
    end
  end
end
