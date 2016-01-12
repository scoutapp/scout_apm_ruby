require 'test_helper'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

class LayawayTest < Minitest::Test
  def test_add_reporting_period
    File.open(DATA_FILE_PATH, 'w') { |file| file.write(Marshal.dump(NEW_FORMAT)) }
    ScoutApm::Agent.instance.start

    data = ScoutApm::Layaway.new
    t = ScoutApm::StoreReportingPeriodTimestamp.new
    data.add_reporting_period(t,ScoutApm::StoreReportingPeriod.new(t))
    assert_equal [TIMESTAMP,t], Marshal.load(File.read(DATA_FILE_PATH)).keys
  end

  def test_merge_reporting_period
    File.open(DATA_FILE_PATH, 'w') { |file| file.write(Marshal.dump(NEW_FORMAT)) }
    ScoutApm::Agent.instance.start

    data = ScoutApm::Layaway.new
    t = ScoutApm::StoreReportingPeriodTimestamp.new
    data.add_reporting_period(TIMESTAMP,ScoutApm::StoreReportingPeriod.new(TIMESTAMP))
    assert_equal [TIMESTAMP], Marshal.load(File.read(DATA_FILE_PATH)).keys
    # TODO - add tests to verify metrics+slow transactions are merged
  end

  TIMESTAMP = ScoutApm::StoreReportingPeriodTimestamp.new(Time.parse("2015-01-01"))
  NEW_FORMAT = {TIMESTAMP => ScoutApm::StoreReportingPeriod.new(TIMESTAMP)} # Format for 1.2+ agents
end