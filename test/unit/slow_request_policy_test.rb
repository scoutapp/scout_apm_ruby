require 'test_helper'

require 'scout_apm/slow_request_policy'
require 'scout_apm/layer'

class FakeRequest
  def initialize(name)
    @name = name
    @root_layer = ScoutApm::Layer.new("Controller", name)
    @root_layer.instance_variable_set("@stop_time", Time.now)
  end
  def unique_name; "Controller/foo/bar"; end
  def root_layer; @root_layer; end
  def set_duration(seconds)
    @root_layer.instance_variable_set("@start_time", Time.now - seconds)
  end
end

class SlowRequestPolicyTest < Minitest::Test
  def test_stored_records_current_time
    test_start = Time.now
    policy = ScoutApm::SlowRequestPolicy.new
    request = FakeRequest.new("users/index")

    policy.stored!(request)
    assert policy.last_seen[request.unique_name] > test_start
  end

  def test_score
    policy = ScoutApm::SlowRequestPolicy.new
    request = FakeRequest.new("users/index")

    request.set_duration(10) # 10 seconds
    policy.last_seen[request.unique_name] = Time.now - 120 # 2 minutes since last seen
    ScoutApm::Agent.instance.request_histograms.add(request.unique_name, 1)

    # Actual value I have in console is 1.499
    assert policy.score(request) > 1.45
    assert policy.score(request) < 1.55
  end
end
