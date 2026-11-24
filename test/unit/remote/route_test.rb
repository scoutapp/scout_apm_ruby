require 'test_helper'

class RouterTest < Minitest::Test
  def test_router_handles_record
    recorder = stub
    router = ScoutApm::Remote::Router.new(recorder, logger)
    message = ScoutApm::Remote::Message.new("record", "record!", 1).encode

    recorder.expects(:record!).with(1)

    router.handle(message)
  end

  def test_router_raises_on_unknown_types
    recorder = stub
    router = ScoutApm::Remote::Router.new(recorder, logger)
    message = ScoutApm::Remote::Message.new("something_else", "record!", 1).encode

    recorder.expects(:record!).never
    assert_raises do
      router.handle(message)
    end
  end

  def test_router_raises_on_unknown_commands
    recorder = stub
    router = ScoutApm::Remote::Router.new(recorder, logger)

    recorder.expects(:foo).never
    assert_raises do
      router.handle(ScoutApm::Remote::Message.new("record", "foo", 1, 2).encode)
    end
  end

  def test_router_only_calls_allowed_commands
    recorder = Object.new
    router = ScoutApm::Remote::Router.new(recorder, logger)
    message = ScoutApm::Remote::Message.new("record", "instance_eval", "@called = true").encode

    assert_raises do
      router.handle(message)
    end
    assert_nil recorder.instance_variable_get(:@called)
  end

  def logger
    @logger ||= Logger.new(logger_io)
  end

  def logger_io
    @logger_io ||= StringIO.new
  end
end
