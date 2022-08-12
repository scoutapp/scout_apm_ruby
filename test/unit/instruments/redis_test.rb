if (ENV["SCOUT_TEST_FEATURES"] || "").include?("instruments")
  require 'test_helper'

  require 'scout_apm/instruments/redis'

  require 'redis'

  class RedisTest < Minitest::Test
    def setup
      @context = ScoutApm::AgentContext.new
      @instance = ScoutApm::Instruments::Redis.new(@context)
      @instrument_manager = ScoutApm::InstrumentManager.new(@context)
      @instance.install(prepend: @instrument_manager.prepend_for_instrument?(@instance.class))
    end

    def test_installs_using_proper_method
      if @instrument_manager.prepend_for_instrument?(@instance.class) == true
        assert ::Redis::Client.ancestors.include?(ScoutApm::Instruments::RedisClientInstrumentationPrepend)
      else
        assert_equal false, ::Redis::Client.ancestors.include?(ScoutApm::Instruments::RedisClientInstrumentationPrepend)
      end
    end
  end
end