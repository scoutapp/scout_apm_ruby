require 'test_helper'

class AgentForkTest < Minitest::Test
  # A fresh, non-singleton Agent backed by real defaults + coercions.
  def build_agent(overrides = {})
    agent = ScoutApm::Agent.new
    overlays = [
      FakeConfigOverlay.new(overrides),
      ScoutApm::Config::ConfigDefaults.new,
      ScoutApm::Config::ConfigNull.new,
    ]
    agent.context.config = ScoutApm::Config.new(agent.context, overlays)
    # Don't register real at_exit handlers from these throwaway agents.
    ScoutApm::Agent::ExitHandler.any_instance.stubs(:install)
    agent
  end

  def test_error_service_enabled_reflects_config
    assert build_agent('errors_enabled' => true).error_service_enabled?
    refute build_agent('errors_enabled' => false).error_service_enabled?
  end

  def test_start_background_worker_survives_thread_alloc_failure
    agent = build_agent('monitor' => true)
    Thread.stubs(:new).raises(ThreadError.new("can't alloc thread"))

    result = agent.start_background_worker(true) # must not raise

    refute result
    refute agent.background_worker_running?
  end

  def test_start_error_service_worker_survives_thread_alloc_failure
    agent = build_agent('monitor' => true, 'errors_enabled' => true)
    Thread.stubs(:new).raises(ThreadError.new("can't alloc thread"))

    result = agent.start_error_service_background_worker # must not raise

    refute result
    refute agent.error_service_background_worker_running?
  end

  def test_stop_threads_for_fork_kills_running_worker
    agent = build_agent('monitor' => true)
    assert agent.start_background_worker(true)
    assert agent.background_worker_running?

    agent.stop_threads_for_fork

    refute agent.background_worker_running?
  end

  def test_stop_threads_for_fork_resets_and_stops_recorder
    agent = build_agent('monitor' => true)
    fake_recorder = Object.new
    def fake_recorder.stop; @stopped = true; end
    def fake_recorder.stopped?; @stopped; end
    agent.context.recorder = fake_recorder

    agent.stop_threads_for_fork

    assert fake_recorder.stopped?, "recorder should be stopped on the fork path"
    assert_nil agent.context.instance_variable_get(:@recorder), "recorder memo should be cleared for lazy rebuild"
  end

  def test_restart_after_fork_is_noop_when_not_started
    agent = build_agent('monitor' => true) # never started
    agent.restart_after_fork
    refute agent.background_worker_running?
  end
end
