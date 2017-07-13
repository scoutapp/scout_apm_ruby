require 'test_helper'

class TrackedRequestDumpAndLoadTest < Minitest::Test
  # TrackedRequest must be marshalable
  def test_marshal_dump_load
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    tr.prepare_to_dump!

    dumped = Marshal.dump(tr)
    loaded = Marshal.load(dumped)
    assert_false loaded.nil?
  end

  def test_restore_store
    faux = ScoutApm::FakeStore.new
    tr = ScoutApm::TrackedRequest.new(faux)
    assert_equal faux, tr.instance_variable_get("@store")

    tr.prepare_to_dump!
    assert_nil tr.instance_variable_get("@store")

    tr.restore_store
    assert_equal ScoutApm::Agent.instance.store, tr.instance_variable_get("@store")
  end
end

class TrackedRequestFlagsTest < Minitest::Test
  def test_set_web
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    assert_false tr.web?
    tr.web!
    assert tr.web?
  end

  def test_set_job
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    assert ! tr.job?
    tr.job!
    assert tr.job?
  end

  def test_set_error
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    assert_false tr.error?
    tr.error!
    assert tr.error?
  end

  def test_set_error_and_web
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    assert_false tr.error?
    assert_false tr.web?

    tr.web!
    assert_false tr.error?
    assert tr.web?

    tr.error!
    assert tr.error?
    assert tr.web?
  end
end

class TrackedRequestLayerManipulationTest < Minitest::Test
  def test_start_layer
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    tr.start_layer(ScoutApm::Layer.new("Foo", "Bar"))

    assert_equal "Foo", tr.current_layer.type
  end

  def test_start_several_layers
    # layers are Controller -> ActiveRecord
    controller_layer = ScoutApm::Layer.new("Controller", "users/index")
    ar_layer = ScoutApm::Layer.new("ActiveRecord", "Users#find")

    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    tr.start_layer(controller_layer)
    tr.start_layer(ar_layer)

    assert_equal "ActiveRecord", tr.current_layer.type

    tr.stop_layer

    assert_equal "Controller", tr.current_layer.type
  end
end
