require 'test_helper'
require 'scout_apm/utils/queue_with_timeout'

class QueueWithTimeoutTest < Minitest::Test
  QueueWithTimeout = ScoutApm::Utils::QueueWithTimeout

  def test_full
    q = QueueWithTimeout.new(1)
    assert_equal(false, q.full?)
    q << "a"
    assert_equal(true, q.full?)
  end

  def test_false_if_full
    q = QueueWithTimeout.new(1)
    assert_equal(true,  q << "a")
    assert_equal(false, q << "b")
  end

  def test_push_pop
    q = QueueWithTimeout.new
    q << "a"
    q << "b"
    assert_equal("a", q.shift)
    assert_equal("b", q.shift)
  end

  def test_blocking_pop
    q = QueueWithTimeout.new
    value_received = nil

    t = Thread.new do
      value_received = q.shift(true)
    end

    q << "a"
    sleep(0.001) # gives thread a chance to wake up

    assert_equal("a", value_received)
  end

  def test_blocking_with_timeout
    q = QueueWithTimeout.new
    value_received = nil
    exception_caught = nil

    timeout = 0.01
    # Expects to time out
    t = Thread.new do
      begin
        value_received = q.shift(true, timeout)
      rescue => e
        exception_caught = e
      end
    end

    sleep(timeout * 2)
    q << "a"
    sleep(0.001) # gives thread a chance to wake up

    assert_nil(value_received)
    assert_equal(ThreadError, exception_caught.class)
    assert_equal("queue empty", exception_caught.message)
  end

  def test_blocking_with_data_before_timeout
    q = QueueWithTimeout.new
    value_received = nil
    exception_caught = nil

    timeout = 10.0
    # Expects to not time out
    t = Thread.new do
      begin
        value_received = q.shift(true, timeout)
      rescue => e
        exception_caught = e
      end
    end

    sleep(0.001)
    q << "a"
    sleep(0.001) # gives thread a chance to wake up

    assert_equal("a", value_received)
    assert_nil(exception_caught)
  end

  def test_blocking_with_data_before_shift
    q = QueueWithTimeout.new
    value_received = nil
    exception_caught = nil

    timeout = 1
    sleep(0.001)
    q << "a"

    t = Thread.new do
      begin
        value_received = q.shift(true, timeout)
      rescue => e
        exception_caught = e
      end
    end

    sleep(0.001) # gives thread a chance to wake up

    assert_equal("a", value_received)
    assert_nil(exception_caught)
  end
end
