require 'test_helper'

class TrackedRequestDumpAndLoadTest < Minitest::Test
  # TrackedRequest must be marshalable
  def test_marshal_dump_load
    tr = ScoutApm::TrackedRequest.new(ScoutApm::AgentContext.new, ScoutApm::FakeStore.new)
    tr.prepare_to_dump!

    dumped = Marshal.dump(tr)
    loaded = Marshal.load(dumped)
    assert_false loaded.nil?
  end

  def test_restore_store
    faux_store = ScoutApm::FakeStore.new
    context = ScoutApm::AgentContext.new
    tr = ScoutApm::TrackedRequest.new(context, faux_store)
    assert_equal faux_store, tr.instance_variable_get("@store")

    tr.prepare_to_dump!
    assert_nil tr.instance_variable_get("@store")

    tr.restore_store
    assert_equal context.store, tr.instance_variable_get("@store")
  end
end

class TrackedRequestLayerManipulationTest < Minitest::Test
  def test_start_layer
    tr = ScoutApm::TrackedRequest.new(ScoutApm::AgentContext.new, ScoutApm::FakeStore.new)
    tr.start_layer(ScoutApm::Layer.new("Foo", "Bar"))

    assert_equal "Foo", tr.current_layer.type
  end

  def test_start_several_layers
    # layers are Controller -> ActiveRecord
    controller_layer = ScoutApm::Layer.new("Controller", "users/index")
    ar_layer = ScoutApm::Layer.new("ActiveRecord", "Users#find")

    tr = ScoutApm::TrackedRequest.new(ScoutApm::AgentContext.new, ScoutApm::FakeStore.new)
    tr.start_layer(controller_layer)
    tr.start_layer(ar_layer)

    assert_equal "ActiveRecord", tr.current_layer.type

    tr.stop_layer

    assert_equal "Controller", tr.current_layer.type
  end
end
