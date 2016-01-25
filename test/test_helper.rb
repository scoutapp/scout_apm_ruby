
require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/pride'

require 'pry'

require 'scout_apm'

Kernel.module_eval do
  # Unset a constant without private access.
  def self.const_unset(const)
    self.instance_eval { remove_const(const) }
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
    ScoutApm::Agent.instance.shutdown if ScoutApm::Agent.instance.started?
    File.delete(DATA_FILE_PATH) if File.exist?(DATA_FILE_PATH)
    ScoutApm::Agent.class_variable_set("@@instance",nil)
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

  DATA_FILE_DIR = File.dirname(__FILE__) + '/tmp'
  DATA_FILE_PATH = "#{DATA_FILE_DIR}/scout_apm.db"
end
