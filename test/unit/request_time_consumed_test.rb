require 'test_helper'

require 'scout_apm/request_time_consumed'

module ScoutApm
  class RequestTimeConsumedTest < Minitest::Test
    def setup
      @rtc = ScoutApm::RequestTimeConsumed.new
    end

    def test_insert_new_times
      @rtc.add("Controller/Foo", 1.5)
      @rtc.add("Controller/Foo", 2.75)
      assert_equal 4.25, @rtc.total_time_for("Controller/Foo")
    end

    def test_insert_tracks_endpoints_separately
      @rtc.add("Controller/Foo", 1.5)
      @rtc.add("Controller/Foo", 2.75)
      @rtc.add("Controller/Bar", 5)
      @rtc.add("Controller/Bar", 5)
      assert_equal 4.25, @rtc.total_time_for("Controller/Foo")
      assert_equal 10.0, @rtc.total_time_for("Controller/Bar")
    end

    def test_calculates_percent_of_total
      @rtc.add("Controller/Foo", 1)
      @rtc.add("Controller/Bar", 4)
      assert_equal 0.2, @rtc.percent_of_total("Controller/Foo")
      assert_equal 0.8, @rtc.percent_of_total("Controller/Bar")
    end

    def test_counts_total_call_count
      @rtc.add("Controller/Foo", 1)
      @rtc.add("Controller/Foo", 1)
      @rtc.add("Controller/Foo", 1)
      @rtc.add("Controller/Bar", 4)
      assert_equal 3, @rtc.call_count_for("Controller/Foo")
      assert_equal 1, @rtc.call_count_for("Controller/Bar")
    end

    def test_percent_of_total_is_0_with_no_data
      assert_equal 0.0, @rtc.percent_of_total("Controller/Foo")
    end
  end
end
