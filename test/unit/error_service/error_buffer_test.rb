require "test_helper"

class ErrorBufferTest < Minitest::Test
  class FakeError < StandardError
  end

  def test_captures_and_stores_exceptions_and_env
    eb = ScoutApm::ErrorService::ErrorBuffer.new(context)
    eb.capture(ex, env)
  end

  def test_only_captures_relevant_environment
    config = make_fake_config(
      'errors_enabled' => true,
      'errors_env_capture' => %w(ANOTHER_HEADER),
      'collect_remote_ip' => true
    )

    test_context = ScoutApm::AgentContext.new().tap { |c| c.config = config }
    ScoutApm::Agent.instance.stub(:context, test_context) do
      eb = ScoutApm::ErrorService::ErrorBuffer.new(test_context)
      eb.capture(ex, env)
      exceptions = eb.instance_variable_get(:@error_records)
      assert_equal 1, exceptions.length

      exception = exceptions[0]
      expected_env_keys = [
        "REQUEST_METHOD",
        "ANOTHER_HEADER",
        "HTTP_X_FORWARDED_FOR",
        "HTTP_USER_AGENT",
        "HTTP_REFERER",
        "HTTP_ACCEPT_ENCODING",
        "HTTP_ORIGIN",
      ].to_set

      assert_equal expected_env_keys, exception.environment.keys.to_set
    end
  end

  #### Helpers

  def context
    ScoutApm::AgentContext.new
  end

  def env
    {
      "REQUEST_METHOD" => "GET",
      "SERVER_NAME" => "localhost",
      "SERVER_PORT" => "3000",
      "PATH_INFO" => "/test",
      "HTTP_VERSION" => "HTTP/1.1",
      "HTTP_USER_AGENT" => "TestAgent",
      "HTTP_ACCEPT" => "text/html",
      "HTTP_HOST" => "localhost:3000",
      "HTTP_X_FORWARDED_FOR" => "123.345.67.89",
      "HTTP_X_FORWARDED_PROTO" => "http",
      "rack.url_scheme" => "http",
      "REMOTE_ADDR" => "123.345.67.89",
      "ANOTHER_HEADER" => "value",
      "HTTP_REFERER" => "http://example.com",
      "HTTP_ACCEPT_ENCODING" => "gzip, deflate",
      "HTTP_ORIGIN" => "http://example.com",
    }
  end

  def ex(msg="Whoops")
    FakeError.new(msg)
  end
end