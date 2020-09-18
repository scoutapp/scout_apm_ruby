module ScoutApm
  module ErrorService
    class Sidekiq
      def initialize
        @context = ScoutApm::Agent.instance.context
      end

      def install
        return false unless defined?(::Sidekiq)

        if ::Sidekiq::VERSION < "3"
          install_sidekiq_with_middleware
        else
          install_sidekiq_with_error_handler
        end

        true
      end

      def install_sidekiq_with_middleware
        # old behavior
        ::Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add ScoutApm::ErrorService::Sidekiq::SidekiqExceptionMiddleware
          end
        end
      end

      def install_sidekiq_with_error_handler
        ::Sidekiq.configure_server do |config|
          config.error_handlers << proc { |ex, context|
            context = ScoutApm::Agent.instance.context

            # Bail out early, and reraise if the error is not interesting.
            if context.ignored_exceptions.ignored?(exception)
              raise
            end

            # Capture the error for further processing and shipping
            context.error_buffer.capture(exception, context.merge(custom_controller: context["class"]))
          }
        end
      end

      class SidekiqExceptionMiddleware
        def call(worker, msg, queue)
          yield
        rescue => exception
          context = ScoutApm::Agent.instance.context

          # Bail out early, and reraise if the error is not interesting.
          if context.ignored_exceptions.ignored?(exception)
            raise
          end

          # Capture the error for further processing and shipping
          context.error_buffer.capture(
            exception,
            {
              custom_params: msg,
              custom_controller: msg["class"]
            }
          )

          # Finally, reraise
          raise exception
        end
      end
    end
  end
end
