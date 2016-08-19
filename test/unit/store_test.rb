require 'test_helper'

require 'scout_apm/store'

class FakeFailingLayaway
  def write_reporting_period(rp)
    raise "Always fails. Sucks."
  end
end

class StoreTest < Minitest::Test
  # TODO: Introduce a clock object to avoid having to use 'force'
  def test_writing_layaway_removes_timestamps
    s = ScoutApm::Store.new
    s.track_one!("Controller", "user/show", 10)

    assert_equal(1, s.reporting_periods.size)

    s.write_to_layaway(FakeFailingLayaway.new, true)

    assert_equal({}, s.reporting_periods)
  end
end
