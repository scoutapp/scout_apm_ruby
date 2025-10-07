require 'test_helper'
require 'scout_apm/background_job_integrations/shoryuken'

class ShoryukenTest < Minitest::Test
  ShoryukenIntegration = ScoutApm::BackgroundJobIntegrations::Shoryuken
  ShoryukenMiddleware = ScoutApm::BackgroundJobIntegrations::ShoryukenMiddleware

  def test_middleware_call_job_exception_with_error_monitoring
    # Test that error buffer is called on exception
    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice  
    fake_request.expects(:error!)

    fake_context = mock
    fake_error_buffer = mock
    fake_context.expects(:error_buffer).returns(fake_error_buffer)
    
    expected_env = {
      :custom_controller => "TestWorker",
      :custom_action => "test-queue"
    }
    fake_error_buffer.expects(:capture).with(kind_of(RuntimeError), expected_env)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)
    ScoutApm::Agent.instance.expects(:context).returns(fake_context)

    worker_instance = mock
    worker_instance.expects(:class).returns(mock(to_s: "TestWorker"))
    queue = "test-queue"
    msg = mock
    body = {}

    assert_raises RuntimeError do
      ShoryukenMiddleware.new.call(worker_instance, queue, msg, body) do
        raise RuntimeError, "Job failed"
      end
    end
  end

  def test_middleware_call_activejob_wrapper
    # Test ActiveJob job class extraction
    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice
    fake_request.expects(:error!)

    fake_context = mock
    fake_error_buffer = mock
    fake_context.expects(:error_buffer).returns(fake_error_buffer)
    
    expected_env = {
      :custom_controller => "MyRealJob",  # Should extract from body
      :custom_action => "priority-queue"
    }
    fake_error_buffer.expects(:capture).with(kind_of(RuntimeError), expected_env)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)
    ScoutApm::Agent.instance.expects(:context).returns(fake_context)

    worker_instance = mock
    worker_instance.expects(:class).returns(mock(to_s: "ActiveJob::QueueAdapters::ShoryukenAdapter::JobWrapper"))
    queue = "priority-queue"
    msg = mock
    body = { "job_class" => "MyRealJob" }

    assert_raises RuntimeError do
      ShoryukenMiddleware.new.call(worker_instance, queue, msg, body) do
        raise RuntimeError, "ActiveJob failed"
      end
    end
  end
end