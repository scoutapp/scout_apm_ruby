require 'test_helper'

# Helper to set up and tear down Rage stubs.
# Rage stubs are only defined during tests that need them.
def fake_rage
  return if defined?(::Rage::VERSION)

  Object.const_set(:Rage, Module.new)

  ::Rage.const_set(:VERSION, "1.20.0")

  ::Rage.define_singleton_method(:env) { "test" }
  ::Rage.define_singleton_method(:root) { Pathname.new("/tmp/rage_test_app") }

  # Telemetry system stubs
  ::Rage.const_set(:Telemetry, Module.new)

  handler_klass = Class.new do
    class << self
      attr_accessor :handlers_map

      def handle(*span_ids, with:, except: nil)
        @handlers_map ||= {}
        span_ids.each do |span_id|
          @handlers_map[span_id] ||= Set.new
          @handlers_map[span_id] << with
        end
      end

      def inherited(klass)
        klass.handlers_map = @handlers_map&.dup || {}
      end
    end
  end
  ::Rage::Telemetry.const_set(:Handler, handler_klass)

  span_result_klass = Struct.new(:exception) do
    def error?
      !!exception
    end

    def success?
      !error?
    end
  end
  ::Rage::Telemetry.const_set(:SpanResult, span_result_klass)

  # Configuration stubs
  config_klass = Class.new do
    def initialize
      @telemetry_config = Object.new
      telemetry_handlers = []
      @telemetry_config.define_singleton_method(:use) { |h| telemetry_handlers << h }
      @telemetry_config.define_singleton_method(:handlers) { telemetry_handlers }
    end

    def telemetry
      @telemetry_config
    end
  end
  ::Rage.const_set(:Configuration, config_klass)

  config_instance = ::Rage::Configuration.new
  ::Rage.define_singleton_method(:config) { config_instance }
end

def clean_fake_rage
  Object.send(:remove_const, :Rage) if defined?(::Rage)
end

# Load the Rage instrument files (they need ::Rage::Telemetry::Handler to be defined)
# We define the stubs, load the files, then tests can clean up and re-stub as needed.
fake_rage
require 'scout_apm/instruments/rage'
require 'scout_apm/instruments/rage_telemetry_handler'

class RageFrameworkIntegrationTest < Minitest::Test
  def setup
    super
    clean_fake_rails
    fake_rage
  end

  def teardown
    super
    clean_fake_rails
    clean_fake_rage
  end

  def test_present_when_rage_defined
    integration = ScoutApm::FrameworkIntegrations::Rage.new
    assert integration.present?, "Rage integration should be present when ::Rage is defined"
  end

  def test_name
    integration = ScoutApm::FrameworkIntegrations::Rage.new
    assert_equal :rage, integration.name
  end

  def test_human_name
    integration = ScoutApm::FrameworkIntegrations::Rage.new
    assert_equal "Rage", integration.human_name
  end

  def test_env
    integration = ScoutApm::FrameworkIntegrations::Rage.new
    assert_equal "test", integration.env
  end

  def test_version
    integration = ScoutApm::FrameworkIntegrations::Rage.new
    assert_equal "1.20.0", integration.version
  end

  def test_not_present_when_rails_also_defined
    fake_rails(7)
    integration = ScoutApm::FrameworkIntegrations::Rage.new
    assert_equal false, integration.present?
  end
end

class RageInstrumentTest < Minitest::Test
  def setup
    super
    clean_fake_rails
    fake_rage
    @context = ScoutApm::AgentContext.new
  end

  def teardown
    super
    clean_fake_rails
    clean_fake_rage
  end

  def test_install_registers_telemetry_handler
    instrument = ScoutApm::Instruments::Rage.new(@context)
    instrument.install

    assert instrument.installed?
    handlers = ::Rage.config.telemetry.handlers
    assert handlers.any? { |h| h.is_a?(ScoutApm::Instruments::RageTelemetryHandler) }
  end

  def test_install_is_idempotent
    instrument = ScoutApm::Instruments::Rage.new(@context)
    instrument.install
    instrument.install

    handlers = ::Rage.config.telemetry.handlers
    rage_handlers = handlers.select { |h| h.is_a?(ScoutApm::Instruments::RageTelemetryHandler) }
    assert_equal 1, rage_handlers.size
  end
end

class RageTelemetryHandlerTest < Minitest::Test
  def setup
    super
    clean_fake_rails
    fake_rage
    @handler = ScoutApm::Instruments::RageTelemetryHandler.new
  end

  def teardown
    super
    clean_fake_rails
    clean_fake_rage
    Fiber[:scout_request] = nil
  end

  def test_handler_registers_for_controller_span
    map = ScoutApm::Instruments::RageTelemetryHandler.handlers_map
    assert map.key?("controller.action.process"), "Should handle controller.action.process"
  end

  def test_handler_registers_for_cable_connection_span
    map = ScoutApm::Instruments::RageTelemetryHandler.handlers_map
    assert map.key?("cable.connection.process"), "Should handle cable.connection.process"
  end

  def test_handler_registers_for_cable_action_span
    map = ScoutApm::Instruments::RageTelemetryHandler.handlers_map
    assert map.key?("cable.action.process"), "Should handle cable.action.process"
  end

  def test_handler_registers_for_deferred_task_span
    map = ScoutApm::Instruments::RageTelemetryHandler.handlers_map
    assert map.key?("deferred.task.process"), "Should handle deferred.task.process"
  end

  def test_track_controller_creates_controller_layer
    fake_request = Struct.new(:path).new("/users")
    fake_env = { "REMOTE_ADDR" => "127.0.0.1" }

    @handler.track_controller(
      name: "UsersController#index",
      request: fake_request,
      env: fake_env
    ) { ::Rage::Telemetry::SpanResult.new(nil) }

    req = Fiber[:scout_request]
    assert req, "Should have created a tracked request"
    assert_equal "Controller", req.root_layer.type
    assert_equal "UsersController#index", req.root_layer.name
  end

  def test_track_controller_annotates_uri
    fake_request = Struct.new(:path).new("/users/42")
    fake_env = {}

    @handler.track_controller(
      name: "UsersController#show",
      request: fake_request,
      env: fake_env
    ) { ::Rage::Telemetry::SpanResult.new(nil) }

    req = Fiber[:scout_request]
    assert_equal "/users/42", req.annotations[:uri]
  end

  def test_track_controller_marks_error_on_exception_result
    fake_request = Struct.new(:path).new("/users")
    fake_env = {}
    error = RuntimeError.new("something broke")

    @handler.track_controller(
      name: "UsersController#index",
      request: fake_request,
      env: fake_env
    ) { ::Rage::Telemetry::SpanResult.new(error) }

    req = Fiber[:scout_request]
    assert req.error?, "Request should be marked as errored"
  end

  def test_track_controller_reraises_on_exception
    fake_request = Struct.new(:path).new("/users")
    fake_env = {}

    assert_raises(RuntimeError) do
      @handler.track_controller(
        name: "UsersController#index",
        request: fake_request,
        env: fake_env
      ) { raise RuntimeError, "boom" }
    end

    req = Fiber[:scout_request]
    assert req.error?, "Request should be marked as errored on raised exception"
  end

  def test_track_cable_connection_creates_controller_layer
    fake_env = {}

    @handler.track_cable_connection(
      name: "ApplicationCable::Connection#connect",
      env: fake_env
    ) { ::Rage::Telemetry::SpanResult.new(nil) }

    req = Fiber[:scout_request]
    assert_equal "Controller", req.root_layer.type
    assert_equal "ApplicationCable::Connection#connect", req.root_layer.name
  end

  def test_track_cable_action_creates_controller_layer
    fake_env = {}

    @handler.track_cable_action(
      name: "ChatChannel#receive",
      env: fake_env
    ) { ::Rage::Telemetry::SpanResult.new(nil) }

    req = Fiber[:scout_request]
    assert_equal "Controller", req.root_layer.type
    assert_equal "ChatChannel#receive", req.root_layer.name
  end

  def test_track_deferred_task_creates_queue_and_job_layers
    @handler.track_deferred_task(
      name: "SendEmailTask#perform",
      task_class: "SendEmailTask"
    ) { ::Rage::Telemetry::SpanResult.new(nil) }

    req = Fiber[:scout_request]
    # The root layer should be Queue, with Job as a child
    assert_equal "Queue", req.root_layer.type
    assert_equal "rage_deferred", req.root_layer.name

    job_layer = req.root_layer.children.first
    assert job_layer, "Should have a child Job layer"
    assert_equal "Job", job_layer.type
    assert_equal "SendEmailTask#perform", job_layer.name
  end

  def test_track_deferred_task_marks_error
    error = RuntimeError.new("job failed")

    @handler.track_deferred_task(
      name: "SendEmailTask#perform",
      task_class: "SendEmailTask"
    ) { ::Rage::Telemetry::SpanResult.new(error) }

    req = Fiber[:scout_request]
    assert req.error?, "Request should be marked as errored"
  end
end

class RequestManagerFiberStorageTest < Minitest::Test
  def setup
    super
    clean_fake_rails
    fake_rage
  end

  def teardown
    super
    clean_fake_rails
    clean_fake_rage
    Fiber[:scout_request] = nil
  end

  def test_uses_fiber_storage_under_rage
    storage = ScoutApm::RequestManager.storage
    assert_equal Fiber, storage, "Should use Fiber storage when Rage is defined and Rails is not"
  end

  def test_uses_thread_storage_under_rails
    fake_rails(7)
    storage = ScoutApm::RequestManager.storage
    assert_equal Thread.current, storage, "Should use Thread.current when Rails is defined"
  end

  def test_lookup_creates_request_in_fiber_storage
    req = ScoutApm::RequestManager.lookup
    assert_instance_of ScoutApm::TrackedRequest, req
    assert_equal req, Fiber[:scout_request]
  end
end
