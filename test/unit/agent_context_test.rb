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
end
