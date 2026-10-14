require 'test_helper'

class FalconTest < Minitest::Test
  def setup
    @program_name = $PROGRAM_NAME
    @integration = ScoutApm::ServerIntegrations::Falcon.new(ScoutApm::Agent.instance.logger)
    Object.const_set(:Falcon, Module.new) unless defined?(::Falcon)
  end

  def teardown
    $PROGRAM_NAME = @program_name
    Object.send(:remove_const, :Falcon) if defined?(::Falcon)
  end

  def test_present_when_running_under_falcon
    $PROGRAM_NAME = "/app/bin/falcon"

    assert @integration.present?
    assert_equal :falcon, @integration.name
  end

  def test_not_present_in_other_processes_that_load_falcon
    $PROGRAM_NAME = "/app/bin/sidekiq"

    refute @integration.present?
  end

  def test_defers_starting_in_the_preloading_parent
    assert @integration.forking?
    refute @integration.found?
  end

  def test_starts_the_agent_in_a_forked_worker
    skip "Process._fork requires Ruby 3.1" unless Process.respond_to?(:_fork)

    agent = ScoutApm::Agent.instance
    agent.define_singleton_method(:start) { |*| @started_by_fork = true }
    @integration.install

    reader, writer = IO.pipe
    pid = fork do
      reader.close
      writer.write(agent.instance_variable_get(:@started_by_fork).inspect)
      writer.close
      exit!(0)
    end
    writer.close
    started_in_child = reader.read
    Process.wait(pid)

    assert_equal "true", started_in_child
    assert_nil agent.instance_variable_get(:@started_by_fork)
  ensure
    agent.singleton_class.send(:remove_method, :start)
  end
end
