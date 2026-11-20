require 'test_helper'

require 'scout_apm/fork_safety'

class ForkSafetyTest < Minitest::Test
  def test_install_is_idempotent
    ScoutApm::ForkSafety.install
    before = ScoutApm::ForkSafety.installed?
    ScoutApm::ForkSafety.install
    assert_equal before, ScoutApm::ForkSafety.installed?
  end

  def test_hooks_process_fork_when_supported
    ScoutApm::ForkSafety.install
    if Process.respond_to?(:_fork)
      assert ScoutApm::ForkSafety.installed?
      assert Process.singleton_class.ancestors.include?(ScoutApm::ForkSafety::ProcessHook)
    else
      refute ScoutApm::ForkSafety.installed?
    end
  end

  def test_prepare_and_complete_never_raise
    # Even if the agent's bookkeeping blows up, the fork path must not raise.
    ScoutApm::Agent.instance.stubs(:stop_threads_for_fork).raises(StandardError.new("boom"))
    ScoutApm::Agent.instance.stubs(:restart_after_fork).raises(StandardError.new("boom"))

    ScoutApm::ForkSafety.prepare_for_fork
    ScoutApm::ForkSafety.complete_fork
  end
end
