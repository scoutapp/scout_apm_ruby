require 'test_helper'

class TracerTest < Minitest::Test
  def test_instrument
    recorder = FakeRecorder.new
    ScoutApm::Agent.instance.context.recorder = recorder

    invoked = false
    ScoutApm::Tracer.instrument("Test", "name") do
      invoked = true
    end

    assert invoked, "instrumented code was not invoked"
    assert_recorded(recorder, "Test", "name")
  end

  def test_instrument_included
    recorder = FakeRecorder.new
    ScoutApm::Agent.instance.context.recorder = recorder

    klass = Class.new { include ScoutApm::Tracer }

    invoked = false
    klass.instrument("Test", "name") do
      invoked = true
    end

    assert invoked, "instrumented code was not invoked"
    assert_recorded(recorder, "Test", "name")
  end

  def test_instrument_inside_method
    recorder = FakeRecorder.new
    ScoutApm::Agent.instance.context.recorder = recorder

    klass = Class.new { include ScoutApm::Tracer }
    klass.class_eval %q{
    attr_reader :invoked
    def work
      ScoutApm::Tracer.instrument("Test", "name") do
        @invoked = true
      end
    end
    }
    klass_instance = klass.new
    klass_instance.work

    assert klass_instance.invoked, "instrumented code was not invoked"
    assert_recorded(recorder, "Test", "name")
  end

  def test_instrument_method
    recorder = FakeRecorder.new
    ScoutApm::Agent.instance.context.recorder = recorder

    klass = Class.new do
      include ScoutApm::Tracer

      attr_reader :invoked

      def work
        @invoked = true
      end
      instrument_method :work, :type => "Test", :name => "name"
    end

    instance = klass.new
    instance.work

    assert instance.invoked, "instrumented code was not invoked"
    assert_recorded(recorder, "Test", "name")
  end

  def test_instrument_method_hierarchy
    recorder = FakeRecorder.new

    ScoutApm::Agent.instance.context.recorder = recorder

    parent = Class.new do
      include ScoutApm::Tracer

      attr_reader :invoked

      def work
        @invoked = true
      end
      instrument_method :work, :type => "Test", :name => "name"
    end

    child = Class.new(parent)

    instance = child.new
    instance.work

    assert instance.invoked, "instrumented code was not invoked"
    assert_recorded(recorder, "Test", "name")
  end

  private

  def assert_recorded(recorder, type, name)
    req = recorder.requests.first
    assert req, "recorder recorded no layers"
    assert_equal type, req.root_layer.type
    assert_equal name, req.root_layer.name
  end
end
