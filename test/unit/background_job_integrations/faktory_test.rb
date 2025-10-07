require 'test_helper'
require 'scout_apm/background_job_integrations/faktory'

class FaktoryTest < Minitest::Test
  FaktoryMiddleware = ScoutApm::BackgroundJobIntegrations::FaktoryMiddleware

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
      :custom_controller => "TestJob",
      :custom_action => "critical"
    }
    fake_error_buffer.expects(:capture).with(kind_of(RuntimeError), expected_env)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)
    ScoutApm::Agent.instance.expects(:context).returns(fake_context)

    worker_instance = mock
    job = {
      "queue" => "critical",
      "jobtype" => "TestJob",
      "enqueued_at" => Time.now.iso8601
    }

    assert_raises RuntimeError do
      FaktoryMiddleware.new.call(worker_instance, job) do
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
      :custom_controller => "MyRealJob",  # Should extract from custom.wrapped
      :custom_action => "default"
    }
    fake_error_buffer.expects(:capture).with(kind_of(RuntimeError), expected_env)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)
    ScoutApm::Agent.instance.expects(:context).returns(fake_context)

    # ActiveJob wrapper scenario
    worker_instance = mock
    job = {
      "queue" => "default", 
      "jobtype" => "ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper",
      "custom" => { "wrapped" => "MyRealJob" },
      "created_at" => Time.now.iso8601
    }

    assert_raises RuntimeError do
      FaktoryMiddleware.new.call(worker_instance, job) do
        raise RuntimeError, "ActiveJob failed"
      end
    end
  end

  def test_middleware_call_missing_queue_fallback
    # Test behavior when queue is missing
    fake_request = mock
    fake_request.expects(:annotate_request)
    fake_request.expects(:start_layer).twice
    fake_request.expects(:stop_layer).twice
    fake_request.expects(:error!)

    fake_context = mock
    fake_error_buffer = mock
    fake_context.expects(:error_buffer).returns(fake_error_buffer)
    
    expected_env = {
      :custom_controller => "UnknownJob",  # Fallback when jobtype missing
      :custom_action => nil  # No queue
    }
    fake_error_buffer.expects(:capture).with(kind_of(RuntimeError), expected_env)

    ScoutApm::RequestManager.stubs(:lookup).returns(fake_request)
    ScoutApm::Agent.instance.expects(:context).returns(fake_context)

    worker_instance = mock
    job = {}  # Empty job data

    assert_raises RuntimeError do
      FaktoryMiddleware.new.call(worker_instance, job) do
        raise RuntimeError, "Job failed"
      end
    end
  end
end
