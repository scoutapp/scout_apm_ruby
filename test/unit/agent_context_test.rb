require "test_helper"

require "scout_apm/agent_context"

class AgentContextTest < Minitest::Test
  def test_bootstrap_logger_uses_scout_log_level
    original_log_level = ENV["SCOUT_LOG_LEVEL"]
    ENV["SCOUT_LOG_LEVEL"] = "error"

    assert_equal ::Logger::ERROR, ScoutApm::AgentContext.new.logger.log_level
  ensure
    ENV["SCOUT_LOG_LEVEL"] = original_log_level
  end

  def test_has_error_service_ignored_exceptions
    context = ScoutApm::AgentContext.new
    assert ScoutApm::ErrorService::IgnoredExceptions, context.ignored_exceptions.class
  end

  def test_has_error_buffer
    context = ScoutApm::AgentContext.new
    assert ScoutApm::ErrorService::ErrorBuffer, context.error_buffer.class
  end


  class TestPolicy
    def call(req); 1; end
    def stored!(req); end
  end

  def test_customize_slow_request_policy
    context = ScoutApm::AgentContext.new
    assert 4, context.slow_request_policy.policies

    context.slow_request_policy.add(TestPolicy.new)
    assert 5, context.slow_request_policy.policies
  end

  def test_remote_client_uses_parent_token_and_port
    context = ScoutApm::AgentContext.new
    server = stub(:start => true, :port => 54321)
    ScoutApm::Remote::Server.expects(:new).with { |_bind, port, _router, _logger, token|
      port == 7721 && token.is_a?(String) && token.length == 64
    }.returns(server)

    context.start_remote_server!("127.0.0.1", 7721)
    token = context.instance_variable_get(:@remote_token)

    ScoutApm::Remote::Recorder.expects(:new).with("127.0.0.1", 54321, anything, token)
    context.become_remote_client!("127.0.0.1", 7721)
  end

  def test_remote_server_binds_a_free_port_when_configured_port_is_in_use
    context = ScoutApm::AgentContext.new
    busy = stub(:port => 7721)
    busy.stubs(:start).raises(Errno::EADDRINUSE)
    free = stub(:start => true, :port => 54321)

    ScoutApm::Remote::Server.expects(:new).with { |_b, port, *| port == 7721 }.returns(busy)
    ScoutApm::Remote::Server.expects(:new).with { |_b, port, *| port == 0 }.returns(free)

    context.start_remote_server!("127.0.0.1", 7721)

    ScoutApm::Remote::Recorder.expects(:new).with("127.0.0.1", 54321, anything, anything)
    context.become_remote_client!("127.0.0.1", 7721)
  end

  def test_remote_server_is_only_started_once
    context = ScoutApm::AgentContext.new
    server = stub(:start => true, :port => 7721, :started? => true)
    ScoutApm::Remote::Server.expects(:new).once.returns(server)

    context.start_remote_server!("127.0.0.1", 7721)
    context.start_remote_server!("127.0.0.1", 7721)
  end
end
