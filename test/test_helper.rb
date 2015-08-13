
require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/pride'

require 'pry'

Kernel.module_eval do
  # Unset a constant without private access.
  def self.const_unset(const)
    self.instance_eval { remove_const(const) }
  end
end

# require 'scout_apm'

