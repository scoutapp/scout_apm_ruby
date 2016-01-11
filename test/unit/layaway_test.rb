require 'test_helper'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

class LayawayTest < Minitest::Test
  def test_verifying_old_file_format
    old = {1452533280 => {:metrics => {}, :slow_transactions => {}} }
    ScoutApm::Agent.instance.start
    data = ScoutApm::Layaway.new
    assert_equal({}, data.verify_layaway_file_contents(old))
  end

  def test_verifying_current_format
    t = ScoutApm::StoreReportingPeriodTimestamp.new
    old = {t => ScoutApm::StoreReportingPeriod.new(t) }
    ScoutApm::Agent.instance.start
    data = ScoutApm::Layaway.new
    assert_equal old, data.verify_layaway_file_contents(old)
  end

  def test_add_reporting_period_to_old_data_file
    File.open(DATA_FILE_PATH, 'w') { |file| file.write(Marshal.dump(OLD_FORMAT)) }
    ScoutApm::Agent.instance(force: true)
    data = ScoutApm::Layaway.new
    t = ScoutApm::StoreReportingPeriodTimestamp.new
    data.add_reporting_period(t,ScoutApm::StoreReportingPeriod.new(t))
    assert_equal [t], Marshal.load(File.read(DATA_FILE_PATH)).keys
  end

  def test_add_reporting_period
    File.open(DATA_FILE_PATH, 'w') { |file| file.write(Marshal.dump(NEW_FORMAT)) }
    ScoutApm::Agent.instance.start

    data = ScoutApm::Layaway.new
    t = ScoutApm::StoreReportingPeriodTimestamp.new
    data.add_reporting_period(t,ScoutApm::StoreReportingPeriod.new(t))
    assert_equal [TIMESTAMP,t], Marshal.load(File.read(DATA_FILE_PATH)).keys
  end

  DATA_FILE_PATH = File.dirname(__FILE__) + '/../tmp/scout_apm.db' 
  OLD_FORMAT = {1452533280 => {:metrics => {}, :slow_transactions => {}} } # Pre 1.2 agents used a different file format to store data. 
  TIMESTAMP = ScoutApm::StoreReportingPeriodTimestamp.new(Time.parse("2015-01-01"))
  NEW_FORMAT = {TIMESTAMP => ScoutApm::StoreReportingPeriod.new(TIMESTAMP)} # Format for 1.2+ agents

end