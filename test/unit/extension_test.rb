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

    def thing
      "thing"
    end
  end

  class Derived < Base
    def thing
      super + "!"
    end
  end

  ScoutApm::Extension.apply(Base) do
    def log(arg)
      @sequence << :before
      super
      @sequence << :after
    end
  end

  ScoutApm::Extension.apply(Derived) do
    def thing
      super.upcase
    end
  end

  def test_base
    base = Base.new

    base.log(:super)

    assert_equal [:before, :super, :after], base.sequence
  end

  # def test_derived
  #   derived = Derived.new
  # 
  #   assert_equal "THING!", derived.thing
  # end
end
