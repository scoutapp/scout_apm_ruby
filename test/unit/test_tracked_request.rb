require 'test_helper'

require 'scout_apm/tracked_request'
require 'scout_apm/fake_store'

class TrackedRequestTest < Minitest::Test
  # TrackedRequest must be marshalable
  def test_marshal_dump_load
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    tr.reify!

    dumped = Marshal.dump(tr)
    loaded = Marshal.load(dumped)
    assert ! loaded.nil?
  end

  def test_set_web
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    assert ! tr.web?
    tr.web!
    assert tr.web?
  end

  def test_set_job
    tr = ScoutApm::TrackedRequest.new(ScoutApm::FakeStore.new)
    assert ! tr.job?
    tr.job!
    assert tr.job?
  end
end

