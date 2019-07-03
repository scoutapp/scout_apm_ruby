require 'test_helper'
require 'scout_apm/extension'

class ExtensionTest < Minitest::Test
  class Base
    def initialize
      @sequence = []
    end

    attr :sequence

    def log(arg)
      @sequence << arg
    end
  end

  ScoutApm::Extension.apply(Base) do
    def log(arg)
      @sequence << :before
      super
      @sequence << :after
    end
  end

  def test_module_apply
    base = Base.new

    base.log(:super)

    assert_equal [:before, :super, :after], base.sequence
  end
end
