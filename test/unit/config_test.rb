require 'test_helper'

require 'scout_apm/config'

class ConfigTest < Minitest::Test
  def test_initalize_without_a_config
    conf = ScoutApm::Config.without_file

    # nil for random keys
    assert_nil conf.value("log_file_path")

    # but has values for defaulted keys
    assert conf.value("host")

    # and still reads from ENV
    ENV['SCOUT_CONFIG_TEST_KEY'] = 'testval'
    assert_equal 'testval', conf.value("config_test_key")
  end

  def test_loading_a_file
    set_rack_env("production")

    conf_file = File.expand_path("../../data/config_test_1.yml", __FILE__)
    conf = ScoutApm::Config.with_file(conf_file)

    assert_equal "debug", conf.value('log_level')
    assert_equal "APM Test Conf (Production)", conf.value('name')
  end

  def test_loading_file_without_env_in_file
    conf_file = File.expand_path("../../data/config_test_1.yml", __FILE__)
    conf = ScoutApm::Config.with_file(conf_file, environment: "staging")

    assert_equal "info", conf.value('log_level') # the default value
    assert_equal nil, conf.value('name')         # the default value
  end
end


