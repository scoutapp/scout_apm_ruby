require 'test_helper'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

class LayawayTest < Minitest::Test
  TIMESTAMP = ScoutApm::StoreReportingPeriodTimestamp.new(Time.parse("2015-01-01"))
  NEW_FORMAT = {TIMESTAMP => ScoutApm::StoreReportingPeriod.new(TIMESTAMP)} # Format for 1.2+ agents
end
