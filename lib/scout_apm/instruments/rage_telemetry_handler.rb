# Rage telemetry handler that creates Scout APM layers for controller actions,
# cable/WebSocket actions, and deferred tasks (background jobs).
#
# Registered with Rage's telemetry system via:
#   Rage.config.telemetry.use(ScoutApm::Instruments::RageTelemetryHandler.new)
#
# Each handler method wraps a Rage span with Scout layers, enabling automatic
# tracking of request timing, database queries, external HTTP calls, and errors.

module ScoutApm
  module Instruments
    class RageTelemetryHandler < ::Rage::Telemetry::Handler
      handle "controller.action.process", with: :track_controller
      handle "cable.connection.process", with: :track_cable_connection
      handle "cable.action.process", with: :track_cable_action
      handle "deferred.task.process", with: :track_deferred_task

      # Instruments HTTP controller actions.
      # Creates a "Controller" root layer (e.g. "UsersController#index").
      def track_controller(name:, request:, env:)
        req = ScoutApm::RequestManager.lookup
        req.annotate_request(:uri => request.path) rescue nil

        if ScoutApm::Agent.instance.context.config.value("collect_remote_ip")
          req.context.add_user(:ip => env["REMOTE_ADDR"]) rescue nil
        end

        layer = ScoutApm::Layer.new("Controller", name)
        req.start_layer(layer)
        begin
          result = yield
          if result.error?
            req.error!
            capture_error(result.exception, env)
          end
          result
        rescue => e
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end

      # Instruments cable connection lifecycle (connect/disconnect).
      # Creates a "Controller" layer (e.g. "ApplicationCable::Connection#connect").
      def track_cable_connection(name:, env:)
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("Controller", name)
        req.start_layer(layer)
        begin
          result = yield
          if result.error?
            req.error!
            capture_error(result.exception, env)
          end
          result
        rescue => e
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end

      # Instruments cable channel actions (e.g. receiving a message).
      # Creates a "Controller" layer (e.g. "ChatChannel#receive").
      def track_cable_action(name:, env:)
        req = ScoutApm::RequestManager.lookup
        layer = ScoutApm::Layer.new("Controller", name)
        req.start_layer(layer)
        begin
          result = yield
          if result.error?
            req.error!
            capture_error(result.exception, env)
          end
          result
        rescue => e
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end

      # Instruments deferred task execution (Rage's background job system).
      # Creates a "Queue" + "Job" layer pair (e.g. "SendEmailTask#perform").
      def track_deferred_task(name:, task_class:)
        req = ScoutApm::RequestManager.lookup
        req.start_layer(ScoutApm::Layer.new("Queue", "rage_deferred"))
        started_queue = true
        req.start_layer(ScoutApm::Layer.new("Job", name))
        started_job = true
        begin
          result = yield
          if result.error?
            req.error!
            capture_error(result.exception, {custom_controller: name})
          end
          result
        rescue => e
          req.error!
          raise
        ensure
          req.stop_layer if started_job
          req.stop_layer if started_queue
        end
      end

      private

      def capture_error(exception, env)
        return unless exception
        return unless ScoutApm::ErrorService.enabled?

        context = ScoutApm::Agent.instance.context
        return if context.ignored_exceptions.ignored?(exception)

        context.error_buffer.capture(exception, env)
      rescue
        # Don't let error capture failures affect the request
      end
    end
  end
end
