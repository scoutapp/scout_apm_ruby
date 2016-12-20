# Load & Start simplecov before loading scout_apm
require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/pride'
require 'mocha/mini_test'
require 'pry'


require 'scout_apm'

Kernel.module_eval do
  # Unset a constant without private access.
  def self.const_unset(const)
    self.instance_eval { remove_const(const) }
  end

  def silence_warnings(&block)
    warn_level = $VERBOSE
    $VERBOSE = nil
    result = block.call
    $VERBOSE = warn_level
    result
  end
end

# A test helper class to create a temporary "configuration" we can control entirely purposes
class FakeConfigOverlay
  def initialize(values)
    @values = values
  end

  def value(key)
    @values[key]
  end

  def has_key?(key)
    @values.has_key?(key)
  end
end

class FakeEnvironment
  def initialize(values)
    @values = values
  end

  def method_missing(sym)
    if @values.has_key?(sym)
      @values[sym]
    else
      raise "#{sym} not found in FakeEnvironment"
    end
  end
end

# Helpers available to all tests
class Minitest::Test
  def setup
    reopen_logger
    FileUtils.mkdir_p(DATA_FILE_DIR)
    ENV['SCOUT_DATA_FILE'] = DATA_FILE_PATH
  end

  def teardown
    ScoutApm::Agent.instance.shutdown
    File.delete(DATA_FILE_PATH) if File.exist?(DATA_FILE_PATH)
  end

  def set_rack_env(env)
    ENV['RACK_ENV'] = "production"
    ScoutApm::Environment.instance.instance_variable_set("@env", nil)
  end

  def reopen_logger
    @log_contents = StringIO.new
    @logger = Logger.new(@log_contents)
    ScoutApm::Agent.instance.instance_variable_set("@logger", @logger)
  end

  def make_fake_environment(values)
    FakeEnvironment.new(values)
  end

  def make_fake_config(values)
    ScoutApm::Config.new(FakeConfigOverlay.new(values))
  end

  DATA_FILE_DIR = File.dirname(__FILE__) + '/tmp'
  DATA_FILE_PATH = "#{DATA_FILE_DIR}/scout_apm.db"
end


module CustomAsserts
  def assert_false(thing)
    assert !thing
  end
end

class Minitest::Test
  include CustomAsserts
end
