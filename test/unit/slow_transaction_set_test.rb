require 'test_helper'

require 'scout_apm/slow_transaction_set'
require 'scout_apm/slow_transaction'

class SlowTransactionSetTest < Minitest::Test
  def test_adding_to_empty_set
    set = ScoutApm::SlowTransactionSet.new(3, 1)
    set << make_slow("Controller/Foo")
    assert_equal 1, set.count
  end

  def test_adding_to_partially_full_set
    set = ScoutApm::SlowTransactionSet.new(3, 1)
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    assert_equal 2, set.count
  end

  def test_overflow_of_one_type
    max_size = 3
    set = ScoutApm::SlowTransactionSet.new(max_size, 1)
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    assert_equal max_size, set.count
  end

  def test_eviction_of_overrepresented
    max_size = 3
    set = ScoutApm::SlowTransactionSet.new(max_size, 1)
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Bar")

    # 3 total
    assert_equal max_size, set.count
    assert_equal 1, set.select{|sl| sl.metric_name == "Controller/Bar"}.length
    assert_equal 2, set.select{|sl| sl.metric_name == "Controller/Foo"}.length
  end

  # Fill the set with /Foo records, then add a /Bar to evict. Check that the
  # evicted one was the fastest of the Foos
  def test_eviction_of_fastest
    max_size = 3
    set = ScoutApm::SlowTransactionSet.new(max_size, 1)

    [1,2,3].shuffle.each do |seconds| # Shuffle to remove any assumptions on order
      set << make_slow("Controller/Foo", seconds)
    end
    set << make_slow("Controller/Bar", 8)

    # The foo taking 1 second should be evicted
    assert_equal 2, set.select{|sl| sl.metric_name == "Controller/Foo"}.map{ |sl| sl.total_call_time}.min
  end

  def test_eviction_when_no_overrepresented
    max_size = 4
    fair = 2
    set = ScoutApm::SlowTransactionSet.new(max_size, fair)

    # Full, but each is at fair level
    set << make_slow("Controller/Bar")
    set << make_slow("Controller/Bar")
    set << make_slow("Controller/Foo")
    set << make_slow("Controller/Foo")

    set << make_slow("Controller/Quux")
    assert_equal max_size, set.count
    assert_equal 0, set.select{|sl| sl.metric_name == "Controller/Quux" }.length
  end

  ##############
  #### Helpers
  ##############

  def make_slow(metric, time=5)
    ScoutApm::SlowTransaction.new(
      "http://foo.app/#{metric}",
      metric,
      time,
      {}, # metrics
      {}, # context
      Time.now, # end time
      []) # stackprof
  end
end
