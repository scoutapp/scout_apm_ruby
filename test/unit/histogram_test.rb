require 'test_helper'

require 'scout_apm/histogram'

# These tests assume insertion order.  Because of the approximate nature of
# this data structure, changing the order can slightly change the results,
# causing these tests to fail.  The overall "shape" of the histogram should be
# approximately the same in the case of alternate orders, but I'm punting on
# any attempts to automate that.
class HistogramTest < Minitest::Test
  # When we have enough slots, we don't have any fuzz in the data, so exact numbers.
  def test_histogram_min_and_max_with_big_enough_histogram
    hist = ScoutApm::NumericHistogram.new(10)

    10.times {
      (1..10).to_a.each do |i|
        hist.add(i)
      end
    }

    assert_equal 1, hist.quantile(0)
    assert_equal 10, hist.quantile(100)
  end

  # When we don't have enough slots, we have to approximate the buckets
  # In this case, the true range is 1 through 10, and we only have 5 buckets to allocate.
  # 1 2 3 4 5 6 7 8 9 10 # <-- True Range
  #   x   x   x   x   x  # <-- Where buckets get adjusted to
  def test_histogram_min_and_max_with_fewer_buckets
    hist = ScoutApm::NumericHistogram.new(5)

    10.times {
      (1..10).to_a.each do |i|
        hist.add(i)
      end
    }

    assert_equal 1.5, round(hist.quantile(0), 1)
    assert_equal 9.5, round(hist.quantile(100), 1)
  end

  def test_combine
    hist1 = ScoutApm::NumericHistogram.new(5)
    10.times {
      (1..10).to_a.each do |i|
        hist1.add(i)
      end
    }

    hist2 = ScoutApm::NumericHistogram.new(10)
    10.times {
      (1..10).to_a.each do |i|
        hist2.add(i)
      end
    }

    combined = hist1.combine!(hist2)
    assert_equal 1.5, round(combined.quantile(0), 1)
    assert_equal 9.5, round(combined.quantile(100), 1)
    assert_equal 200, combined.total
  end

  def test_combine_retains_order
    hist1 = ScoutApm::NumericHistogram.new(5)
    10.times {
      (10..50).to_a.each do |i|
        hist1.add(i)
      end
    }

    hist2 = ScoutApm::NumericHistogram.new(10)
    10.times {
      (1..10).to_a.each do |i|
        hist2.add(i)
      end
    }

    combined = hist1.combine!(hist2)
    assert combined.quantile(0) < combined.quantile(100)
  end

  def test_combine_dedups_identicals
    hist1 = ScoutApm::NumericHistogram.new(5)
    hist2 = ScoutApm::NumericHistogram.new(5)
    hist1.add(1)
    hist1.add(2)
    hist2.add(2)
    hist2.add(3)

    combined = hist1.combine!(hist2)
    assert_equal 4, combined.total
    assert_equal [[1, 1], [2, 2], [1, 3]],
      combined.bins.map{|bin| [bin.count, bin.value.to_i] }
  end

  def test_mean
    hist = ScoutApm::NumericHistogram.new(5)
    10.times {
      (1..10).to_a.each do |i|
        hist.add(i)
      end
    }

    assert_equal 5.5, hist.mean
  end

  def test_combine_matches_original_algorithm
    random = Random.new(1)
    100.times do
      hist = random_histogram(random)
      other = random_histogram(random)
      expected = original_combine(bin_pairs(hist), bin_pairs(other), hist.max_bins)

      assert_equal expected, bin_pairs(hist.combine!(other))
    end
  end

  private

  # Ruby 1.8 compatible round with precision
  def round(number, precision)
    ((number * 10**precision).round.to_f) / (10**precision)
  end

  def random_histogram(random)
    hist = ScoutApm::NumericHistogram.new(50)
    random.rand(1..300).times { hist.add(random.rand(1..2000) / 1000.0) }
    hist
  end

  def bin_pairs(hist)
    hist.bins.map { |bin| [bin.value, bin.count] }
  end

  def original_combine(bins, other_bins, max_bins)
    combined = (other_bins + bins).
      group_by { |value, _| value }.
      map { |value, group| [value, group.inject(0) { |sum, (_, count)| sum + count }] }.
      sort_by { |value, _| value }
    original_trim(combined, max_bins)
  end

  def original_trim(bins, max_bins)
    while bins.length > max_bins
      min_delta = Float::MAX
      min_index = 0
      (1...bins.length).each do |index|
        delta = bins[index][0] - bins[index - 1][0]
        if delta < min_delta
          min_delta = delta
          min_index = index
        end
      end

      (left_value, left_count), (right_value, right_count) = bins[min_index - 1], bins[min_index]
      count = left_count + right_count
      bins[min_index - 1, 2] = [[(left_value * left_count + right_value * right_count) / count, count]]
    end
    bins
  end
end

