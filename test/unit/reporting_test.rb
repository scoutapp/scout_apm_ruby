require 'test_helper'

class ReportingTest < Minitest::Test
  class InspectCountingHash < Hash
    attr_reader :pretty_inspect_calls

    def pretty_inspect
      @pretty_inspect_calls = (@pretty_inspect_calls || 0) + 1
      super
    end
  end

  FakeContext = Struct.new(:logger)

  def test_log_deliver_skips_debug_dump_when_debug_is_disabled
    metrics = InspectCountingHash.new
    reporting = ScoutApm::Reporting.new(FakeContext.new(logger_at(::Logger::INFO)))

    reporting.log_deliver(metrics, [], { :agent_time => Time.now.iso8601 }, [], [])

    assert_nil metrics.pretty_inspect_calls
  end

  def test_log_deliver_writes_debug_dump_when_debug_is_enabled
    metrics = InspectCountingHash.new
    output = StringIO.new
    reporting = ScoutApm::Reporting.new(FakeContext.new(logger_at(::Logger::DEBUG, output)))

    reporting.log_deliver(metrics, [], { :agent_time => Time.now.iso8601 }, [], [])

    assert_equal 1, metrics.pretty_inspect_calls
    assert_match(/Metrics:/, output.string)
  end

  private

  def logger_at(level, output = StringIO.new)
    ::Logger.new(output).tap { |logger| logger.level = level }
  end
end
