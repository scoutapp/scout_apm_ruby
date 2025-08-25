require "test_helper"

class ErrorTest < Minitest::Test
  class FakeError < StandardError
  end

  def test_captures_and_stores_exceptions_and_env
    config = make_fake_config(
      'errors_enabled' => true,
      'errors_env_capture' => %w(),
    )
    test_context = ScoutApm::AgentContext.new().tap{|c| c.config = config }
    ScoutApm::Agent.instance.stub(:context, test_context) do
      exwbt = ex.tap do |e|
        e.set_backtrace(["/path/to/file.rb:10:in `method_name'"])
      end
      assert_equal true, ScoutApm::Error.capture("Oh no an error") # Will be of type ScoutApm::Error::Custom
      assert_equal true, ScoutApm::Error.capture("Oh no another error") # Will be of type ScoutApm::Error::Custom

      assert_equal true, ScoutApm::Error.capture("Something went boom", {"boom" => "yes"}, name: "boom_error")
      ScoutApm::Context.current.instance_variable_set(:@extra, {}) # Need to reset as the context/request won't change.

      assert_equal true, ScoutApm::Error.capture("No context or env", name: "another error")
      
      assert_equal true, ScoutApm::Error.capture(ex, context)
      ScoutApm::Context.current.instance_variable_set(:@extra, {})

      assert_equal true, ScoutApm::Error.capture(exwbt, env: env)

      assert_equal false, ScoutApm::Error.capture(Class, env: env)
      assert_equal true, ScoutApm::Error.capture("Name collision", context, env: env, name: "ScoutApm")
      
      begin
        raise StandardError, "Whoops"
      rescue StandardError => e
        assert_equal true, ScoutApm::Error.capture(e, env)
      end

      exceptions = ScoutApm::Agent.instance.context.error_buffer.instance_variable_get(:@error_records)

      assert_equal 8, exceptions.length
      assert_equal "Oh no an error", exceptions[0].message
      assert_equal "ScoutApm::Error::Custom", exceptions[0].exception_class

      # Ensure we capture time and git sha
      refute_nil exceptions[0].git_sha
      assert exceptions[0].agent_time.is_a?(String)

      assert_equal "Oh no another error", exceptions[1].message
      assert_equal "ScoutApm::Error::Custom", exceptions[1].exception_class

      assert_equal "Something went boom", exceptions[2].message
      assert_equal "BoomError", exceptions[2].exception_class
      assert_equal "yes", exceptions[2].context["boom"]

      assert_equal "No context or env", exceptions[3].message
      assert_equal "AnotherError", exceptions[3].exception_class
      assert_equal assert_empty_context, exceptions[3].context

      assert_equal "Whoops", exceptions[4].message
      assert_equal "ErrorTest::FakeError", exceptions[4].exception_class
      assert_equal 123, exceptions[4].context["user_id"]

      assert_equal "/path/to/file.rb:10:in `method_name'", exceptions[5].trace.first

      assert_equal "ScoutApm::Error::Custom", exceptions[6].exception_class
      assert_equal 123, exceptions[6].context["user_id"]
      assert_equal "TestAgent", exceptions[6].environment["HTTP_USER_AGENT"]

      assert_equal "StandardError", exceptions[7].exception_class
    end
  end

  #### Helpers
  def context
    {
      "user_id" => 123,
    }
  end

  def env
    {
      "HTTP_USER_AGENT" => "TestAgent",
    }
  end

  def assert_empty_context
    {user: {}}
  end

  def ex(msg="Whoops")
    FakeError.new(msg)
  end
end
