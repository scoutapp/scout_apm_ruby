require 'test_helper'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

require 'fileutils'
class LayawayTest < Minitest::Test
  def test_uses_DATA_FILE_option
    ScoutApm::Agent.instance.start

    FileUtils.mkdir_p '/tmp/scout_apm_test/data_file_option'

    ENV["SCOUT_DATA_FILE"] = "/tmp/scout_apm_test/data_file_option"

    assert_equal Pathname.new("/tmp/scout_apm_test/data_file_option"), ScoutApm::Layaway.new.directory
  end

  TIMESTAMP = ScoutApm::StoreReportingPeriodTimestamp.new(Time.parse("2015-01-01"))
  NEW_FORMAT = {TIMESTAMP => ScoutApm::StoreReportingPeriod.new(TIMESTAMP)} # Format for 1.2+ agents
end
