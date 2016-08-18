require 'test_helper'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

require 'fileutils'
class LayawayTest < Minitest::Test
  def test_uses_DATA_FILE_option
    FileUtils.mkdir_p '/tmp/scout_apm_test/data_file_option'
    config = FakeConfig.new("data_file" => "/tmp/scout_apm_test/data_file_option")

    assert_equal Pathname.new("/tmp/scout_apm_test/data_file_option"), ScoutApm::Layaway.new(config).directory
  end
end
