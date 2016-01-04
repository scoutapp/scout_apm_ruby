
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
  def set_rack_env(env)
    ENV['RACK_ENV'] = "production"
    ScoutApm::Environment.instance.instance_variable_set("@env", nil)
  end
end
