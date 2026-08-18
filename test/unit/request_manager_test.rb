require 'test_helper'

# Tests for RequestManager's thread-local handling, in particular that a
# TrackedRequest created on one thread is NOT shared with another thread.
#
# ActionController::Live runs the controller action in a child thread and copies
# the parent (Rack) thread's raw Thread.current locals -- including
# :scout_request -- into it. Without protection both threads would share and
# concurrently mutate a single TrackedRequest, racing on @layers/@stopping,
# which drops the transaction and leaks layers. RequestManager must give the
# inheriting thread its own request instead.
class RequestManagerTest < Minitest::Test
  def teardown
    # Never let a test leak the thread-local into sibling tests.
    Thread.current[:scout_request] = nil
  end

  def test_lookup_reuses_the_request_on_the_same_thread
    first  = ScoutApm::RequestManager.lookup
    second = ScoutApm::RequestManager.lookup

    assert_same first, second,
      "lookup should return the same TrackedRequest on repeated calls within one thread"
  end

  def test_lookup_in_a_child_thread_that_inherited_the_local_gets_its_own_request
    parent_request = ScoutApm::RequestManager.lookup
    inherited = Thread.current[:scout_request]

    child_request = nil
    child_local_before = nil

    t = Thread.new do
      # Simulate ActionController::Live copying the parent's raw thread local
      # into the streaming child thread.
      Thread.current[:scout_request] = inherited
      child_local_before = Thread.current[:scout_request]

      child_request = ScoutApm::RequestManager.lookup
    end
    t.join

    # The child observed the inherited (parent's) request as its raw local...
    assert_same parent_request, child_local_before

    # ...but lookup must NOT hand it the parent's request to mutate.
    refute_nil child_request
    refute_same parent_request, child_request,
      "a thread that inherited another thread's :scout_request must get its own TrackedRequest"

    # And the parent's request must be left untouched (still the parent's).
    assert_same parent_request, Thread.current[:scout_request]
  end

  def test_find_treats_a_foreign_thread_request_as_absent
    # A request that reports it was created on a different thread should not be
    # returned by find (so lookup falls through to create).
    foreign = ScoutApm::TrackedRequest.new(ScoutApm::Agent.instance.context, ScoutApm::FakeStore.new)
    foreign.stubs(:creating_thread_id).returns(Thread.current.object_id + 1)
    Thread.current[:scout_request] = foreign

    assert_nil ScoutApm::RequestManager.find,
      "find should treat a request created on another thread as absent"
  end

  def test_find_returns_a_same_thread_request
    own = ScoutApm::RequestManager.lookup
    assert_same own, ScoutApm::RequestManager.find
  end
end
