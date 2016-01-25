require 'test_helper'

require 'scout_apm/config'

class ConfigTest < Minitest::Test
  def test_initalize_without_a_config
    conf = ScoutApm::Config.new(nil)

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
    conf = ScoutApm::Config.new(conf_file)

    assert_equal "debug", conf.value('log_level')
    assert_equal "APM Test Conf (Production)", conf.value('name')
  end

  # Ensure a bad config file doesn't cause an exception when accessing a config value
  def test_config_value_with_bad_config
    ScoutApm::Agent.class_variable_set("@@instance",nil) # need to reset this so we're ready with a new agent
    agent = ScoutApm::Agent.instance(:config_path => File.expand_path("../../data/bad_config.yml", __FILE__))
    no_error = true
    begin
      agent.config.value('monitor')
    rescue Exception => e
      no_error = false
    end
    assert no_error, "Error fetching config value w/bad config file: #{e.message if e}"
  end
end

