require 'test_helper'
require 'scout_apm/request_manager'
require 'scout_apm/background_job_integrations/sidekiq'

class SidekiqTest < Minitest::Test
  SidekiqIntegration = ScoutApm::BackgroundJobIntegrations::Sidekiq
  SidekiqMiddleware = ScoutApm::BackgroundJobIntegrations::SidekiqMiddleware

  ########################################
  # Install
  ########################################
  if (ENV["SCOUT_TEST_FEATURES"] || "").include?("sidekiq_install")
    require 'sidekiq'

    # Sidekiq::CLI needs to be defined in order for `Sidekiq.configure_server` to work
    Sidekiq::CLI = nil

    def test_starts_on_startup
      ::ScoutApm::Agent.any_instance.expects(:start)
      SidekiqIntegration.new.install
      ::Sidekiq.configure_server do |config|
        config[:lifecycle_events][:startup].map(&:call)
      end
    end
  end

  ########################################
  # Middleware
  ########################################
  def test_middleware_call_happy_path
    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice
    fake_request.expects(:error!).never

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)

    block_called = false
    msg = { 'class' => 'MyJobClass',
            'created_at' => Time.now }

    SidekiqMiddleware.new.call(nil, msg, "defaultqueue") { block_called = true }
    assert_equal true, block_called
  end

  def test_middleware_call_job_exception
    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice
    fake_request.expects(:error!)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)

    msg = { 'class' => 'MyJobClass',
            'created_at' => Time.now }

    assert_raises RuntimeError do
      SidekiqMiddleware.new.call(nil, msg, "defaultqueue") { raise "TheJobFailed" }
    end
  end

  def test_middleware_call_edge_cases
    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice
    fake_request.expects(:error!)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)

    # msg doesn't have anything
    msg = { }

    assert_raises RuntimeError do
      SidekiqMiddleware.new.call(nil, msg, "defaultqueue") { raise "TheJobFailed" }
    end
  end

  ########################################
  # Job Class Determination
  ########################################
  def test_job_class_name_normally
    msg = { 'class' => 'AGreatJob' }
    assert_equal 'AGreatJob', SidekiqMiddleware.new.job_class(msg)
  end

  def test_job_class_name_activejob
    msg = { 'class' => 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper',
            'wrapped' => 'RealJobClass' }
    assert_equal 'RealJobClass', SidekiqMiddleware.new.job_class(msg)
  end

  def test_job_class_name_error_default
    msg = {}
    assert_equal 'UnknownJob', SidekiqMiddleware.new.job_class(msg)
  end

  ########################################
  # Latency Calculation
  ########################################
  def test_latency_from_created_at
    # Created at time 80, but now it is 200. Latency was 120
    msg = if SidekiqMiddleware.sidekiq_version_8?
            { 'created_at' => 80000 } # milliseconds for Sidekiq 8+
          else
            { 'created_at' => 80 }
          end
    assert_equal 120, SidekiqMiddleware.new.latency(msg, 200)
  end

  def test_latency_from_enqueued_at
    # Created at time 80, but now it is 200. Latency was 120
    msg = if SidekiqMiddleware.sidekiq_version_8?
            { 'enqueued_at' => 80000 } # milliseconds for Sidekiq 8+
          else
            { 'enqueued_at' => 80 }
          end
    assert_equal 120, SidekiqMiddleware.new.latency(msg, 200)
  end

  def test_latency_fallback
    # No created at time, so fall back to 0
    msg = {}
    assert_equal 0, SidekiqMiddleware.new.latency(msg, 200)
  end

  ########################################
  # Job Arguments Capture
  ########################################
  def test_capture_job_args_when_enabled_with_valid_job
    test_job_class = Class.new do
      def self.name
        'TestJobWithArgs'
      end

      def perform(user_id, email, filter_param, dict_val)
      end
    end

    Object.const_set('TestJobWithArgs', test_job_class)

    SidekiqMiddleware.any_instance.stubs(:capture_job_args?).returns(true)
    SidekiqMiddleware.any_instance.stubs(:filtered_params_config).returns(["filter_param"])

    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)
    ScoutApm::Context.expects(:add).with({ user_id: 123, email: 'test@example.com', filter_param: '[FILTERED]', dict_val: '[UNSUPPORTED TYPE]' })

    msg = {
      "class" => SidekiqMiddleware::ACTIVE_JOB_KLASS,
      "wrapped" => "TestJobWithArgs",
      'args' => [{ 'arguments' => [123, 'test@example.com', 'secret', {a: 1}] }]
    }

    block_called = false
    SidekiqMiddleware.new.call(nil, msg, "defaultqueue") { block_called = true }
    assert block_called

    Object.send(:remove_const, 'TestJobWithArgs')
  end
end
