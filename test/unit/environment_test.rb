require 'test_helper'

require 'scout_apm/environment'

class EnvironmentTest < Minitest::Test
  def teardown
    clean_fake_rails
    clean_fake_sinatra
  end

  def test_framework_rails
    fake_rails(2)
    assert_equal :rails, ScoutApm::Environment.send(:new).framework

    clean_fake_rails
    fake_rails(3)
    assert_equal :rails3_or_4, ScoutApm::Environment.send(:new).framework

    clean_fake_rails
    fake_rails(4)
    assert_equal :rails3_or_4, ScoutApm::Environment.send(:new).framework
  end

  def test_framework_sinatra
    fake_sinatra
    assert_equal :sinatra, ScoutApm::Environment.send(:new).framework
  end

  def test_framework_ruby
    assert_equal :ruby, ScoutApm::Environment.send(:new).framework
  end
end
