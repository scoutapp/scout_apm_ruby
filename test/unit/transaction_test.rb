require 'test_helper'

class TransactionTest < Minitest::Test
  def test_ignore
    recorder = FakeRecorder.new
    ScoutApm::Agent.instance.context.recorder = recorder

    ScoutApm::Tracer.instrument("Controller", "foo/bar") do
      ScoutApm::Transaction.ignore!
    end

    assert_equal 0, recorder.requests.length
  end

  def test_rename_request
    recorder = FakeRecorder.new
    ScoutApm::Agent.instance.context.recorder = recorder

    ScoutApm::Tracer.instrument("Controller", "old") do
      ScoutApm::Tracer.instrument("View", "foo/bar") do
        ScoutApm::Transaction.rename("new")
      end
    end

    assert_equal 1, recorder.requests.length
    req = recorder.requests[0]
    assert_equal "new", req.root_layer.name
  end
end
