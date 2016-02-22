require 'test_helper'

require 'scout_apm/histogram'

class HistogramTest < Minitest::Test
  # When we have enough slots, we don't have any fuzz in the data, so exact numbers.
  def test_histogram_min_and_max_with_big_enough_histogram
    hist = ScoutApm::NumericHistogram.new(10)

    10.times {
      (1..10).to_a.shuffle.each do |i|
        hist.add(i)
      end
    }

    assert_equal 1, hist.quantile(0)
    assert_equal 10, hist.quantile(100)
  end

  # When we don't have enough slots, we have to approximate the buckets
  # In this case, the true range is 1 through 10, and we only have 5 buckets to allocate.
  # 1 2 3 4 5 6 7 8 9 10 # <-- True Range
  # x   x   x   x   x    # <-- Where buckets get adjusted to
  def test_histogram_min_and_max_with_fewer_buckets
    hist = ScoutApm::NumericHistogram.new(5)

    10.times {
      (1..10).to_a.shuffle.each do |i|
        hist.add(i)
      end
    }

    assert_equal 1, hist.quantile(0)
    assert_equal 9, hist.quantile(100)
  end

  def test_combine
    hist1 = ScoutApm::NumericHistogram.new(5)
    10.times {
      (1..10).to_a.shuffle.each do |i|
        hist1.add(i)
      end
    }

    hist2 = ScoutApm::NumericHistogram.new(10)
    10.times {
      (1..10).to_a.shuffle.each do |i|
        hist2.add(i)
      end
    }

    combined = hist1.combine!(hist2)
    assert_equal 1, combined.quantile(0)
    assert_equal 9, combined.quantile(100)
    assert_equal 200, combined.total
  end
end

