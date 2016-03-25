require 'test_helper'

require 'scout_apm/slow_job_policy'

class SlowJobPolicyTest < Minitest::Test
  def test_first_call_is_not_slow
    policy = ScoutApm::SlowJobPolicy.new
    assert !policy.slow?("TestWorker", 10)
  end

  # All of these get faster and faster, so none are marked as slow.
  def test_fast_calls_are_not_slow
    policy = ScoutApm::SlowJobPolicy.new
    assert !policy.slow?("TestWorker", 10)
    assert !policy.slow?("TestWorker", 8)
    assert !policy.slow?("TestWorker", 6)
    assert !policy.slow?("TestWorker", 4)
    assert !policy.slow?("TestWorker", 2)
  end

  def test_slow_calls_are_marked_as_slow
    policy = ScoutApm::SlowJobPolicy.new
    policy.slow?("TestWorker", 10) # Prime it with a not-slow

    assert policy.slow?("TestWorker", 12)
    assert policy.slow?("TestWorker", 14)
    assert policy.slow?("TestWorker", 16)
    assert policy.slow?("TestWorker", 18)
  end

  def test_mix_of_fast_and_slow
    policy = ScoutApm::SlowJobPolicy.new
    policy.slow?("TestWorker", 10) # Prime it with a not-slow

    assert policy.slow?("TestWorker", 12)
    assert !policy.slow?("TestWorker", 8)
    assert policy.slow?("TestWorker", 11)
    assert !policy.slow?("TestWorker", 6)
  end

  def test_different_workers_dont_interfere
    policy = ScoutApm::SlowJobPolicy.new
    policy.slow?("TestWorker", 10) # Prime it with a not-slow
    policy.slow?("OtherWorker", 1.0) # Prime it with a not-slow

    assert !policy.slow?("TestWorker", 8)
    assert policy.slow?("OtherWorker", 2)
    assert !policy.slow?("TestWorker", 1)
    assert policy.slow?("OtherWorker", 3)
    assert policy.slow?("TestWorker", 12)
    assert !policy.slow?("OtherWorker", 1)
    assert policy.slow?("TestWorker", 11)
    assert policy.slow?("OtherWorker", 4)
  end
end
