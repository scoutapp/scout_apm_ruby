module ScoutApm
  module ErrorService
    class SidekiqException
      def call(worker, msg, queue)
        yield
      rescue => exception
        ScoutApm::ErrorService.notify(exception, {custom_params: msg, custom_controller: msg["class"]})
        raise exception
      end
    end
  end

  if defined?(::Sidekiq)
    if ::Sidekiq::VERSION < "3"
      # old behavior
      ::Sidekiq.configure_server do |config|
        config.server_middleware do |chain|
          chain.add ScoutApm::ErrorService::SidekiqException
        end
      end
    else
      ::Sidekiq.configure_server do |config|
        config.error_handlers << proc { |ex, context| ScoutApm::ErrorService.notify(ex, context.merge(custom_controller: context["class"])) }
      end
    end
  end
end
