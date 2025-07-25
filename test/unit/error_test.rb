require "test_helper"

class ErrorTest < Minitest::Test
  class FakeError < StandardError
  end

  def test_captures_and_stores_exceptions_and_env
    config = make_fake_config(
      'errors_enabled' => true,
    )
    test_context = ScoutApm::AgentContext.new().tap{|c| c.config = config }
    ScoutApm::Agent.instance.stub(:context, test_context) do
      exwbt = ex.tap do |e|
        e.set_backtrace(["/path/to/file.rb:10:in `method_name'"])
      end
      assert_equal true, ScoutApm::Error.capture("Oh no an error") # Will be of type CustomError
      assert_equal true, ScoutApm::Error.capture("Something went boom", {"boom" => "yes"}, name: "boom_error")
      assert_equal true, ScoutApm::Error.capture("No env", name: "another error")
      assert_equal true, ScoutApm::Error.capture(ex, env)
      assert_equal true, ScoutApm::Error.capture(exwbt, env)
      assert_equal false, ScoutApm::Error.capture(Class, env)

      exceptions = ScoutApm::Agent.instance.context.error_buffer.instance_variable_get(:@error_records)

      assert_equal 5, exceptions.length
      assert_equal "Oh no an error", exceptions[0].message
      assert_equal "CustomError", exceptions[0].exception_class

      assert_equal "Something went boom", exceptions[1].message
      assert_equal "BoomError", exceptions[1].exception_class

      assert_equal "No env", exceptions[2].message
      assert_equal "AnotherError", exceptions[2].exception_class

      assert_equal "Whoops", exceptions[3].message
      assert_equal "ErrorTest::FakeError", exceptions[3].exception_class

      assert_equal "/path/to/file.rb:10:in `method_name'", exceptions[4].trace.first
    end
  end

  #### Helpers
  def env
    {}
  end

  def ex(msg="Whoops")
    FakeError.new(msg)
  end
end
