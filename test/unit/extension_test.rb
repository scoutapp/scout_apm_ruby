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
	
	module Overrides
		extend ScoutApm::Extension
		
		def log(arg)
			@sequence << :before
			super
			@sequence << :after
		end
	end
	
	Overrides.apply(Base)
	
	def test_module_apply
		base = Base.new
		
		base.log(:super)
		
		assert_equal base.sequence, [:before, :super, :after]
	end
end
