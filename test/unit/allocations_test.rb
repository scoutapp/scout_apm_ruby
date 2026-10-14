require 'test_helper'

class AllocationsTest < Minitest::Test
  def count
    ScoutApm::Instruments::Allocations.count
  end

  def test_counts_only_the_running_fibers_allocations
    skip "Allocation tracking is not enabled on this platform" unless ScoutApm::Instruments::Allocations::ENABLED

    heavy = Fiber.new do
      start = count
      5.times do
        20_000.times { Object.new }
        Fiber.yield
      end
      count - start
    end

    light_start = count
    5.times do
      heavy.resume
      10.times { Object.new }
    end
    heavy_allocations = heavy.resume
    light_allocations = count - light_start

    assert_operator heavy_allocations, :>=, 100_000
    assert_operator light_allocations, :<, 1_000
  end

  def test_counts_keep_increasing_within_a_fiber
    skip "Allocation tracking is not enabled on this platform" unless ScoutApm::Instruments::Allocations::ENABLED

    before = count
    1_000.times { Object.new }

    assert_operator count - before, :>=, 1_000
  end
end
