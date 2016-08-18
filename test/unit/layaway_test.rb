require 'test_helper'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

require 'fileutils'
class LayawayTest < Minitest::Test
  def test_directory_uses_DATA_FILE_option
    FileUtils.mkdir_p '/tmp/scout_apm_test/data_file_option'
    config = make_fake_config("data_file" => "/tmp/scout_apm_test/data_file_option")

    assert_equal Pathname.new("/tmp/scout_apm_test/data_file_option"), ScoutApm::Layaway.new(config, ScoutApm::Agent.instance.environment).directory
  end

  def test_directory_looks_for_root_slash_tmp
    FileUtils.mkdir_p '/tmp/scout_apm_test/tmp'
    config = make_fake_config({})
    env = make_fake_environment(:root => "/tmp/scout_apm_test")

    assert_equal Pathname.new("/tmp/scout_apm_test/tmp"), ScoutApm::Layaway.new(config, env).directory
  end
end
