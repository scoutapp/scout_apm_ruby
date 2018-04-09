require 'test_helper'

class TransactionCallbacksTest < Minitest::Test

  # This is more of an integration test to ensure that we don't break TrackedRequest.
  def test_broken_callback_does_not_break_tracked_request
    ScoutApm::Extensions::Config.add_transaction_callback(BrokenCallback)

    controller_layer = ScoutApm::Layer.new("Controller", "users/index")

    tr = ScoutApm::TrackedRequest.new(ScoutApm::AgentContext.new, ScoutApm::FakeStore.new)
    tr.start_layer(controller_layer)
    tr.stop_layer
  end

  def test_callback_runs
    ScoutApm::Extensions::Config.add_transaction_callback(TransactionCallback)

    controller_layer = ScoutApm::Layer.new("Controller", "users/index")

    tr = ScoutApm::TrackedRequest.new(ScoutApm::AgentContext.new, ScoutApm::FakeStore.new)
    tr.start_layer(controller_layer)
    tr.stop_layer

    assert Thread.current[:transaction_callback_output]
  end

  # Doesn't inherit from TransactionCallbackBase
  class BrokenCallback
  end

  # Sets a Thread local so we can verify that the callback ran.
  class TransactionCallback < ScoutApm::Extensions::TransactionCallbackBase
    def call
      Thread.current[:transaction_callback_output] = true
    end
  end

end