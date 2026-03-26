if (ENV["SCOUT_TEST_FEATURES"] || "").include?("instruments")
  require 'test_helper'

  require 'scout_apm/instruments/http'

  require 'http'

  class HttpTest < Minitest::Test
    def setup
      @context = ScoutApm::AgentContext.new
      @instance = ScoutApm::Instruments::HTTP.new(@context)
      @instrument_manager = ScoutApm::InstrumentManager.new(@context)
      @instance.install(prepend: @instrument_manager.prepend_for_instrument?(@instance.class))
    end

    def test_installs_using_proper_method
      if @instrument_manager.prepend_for_instrument?(@instance.class) == true
        if Gem::Version.new(::HTTP::VERSION) >= Gem::Version.new("6.0.0")
          assert ::HTTP::Client.ancestors.include?(ScoutApm::Instruments::HTTPInstrumentationPrependV6)
        else
          assert ::HTTP::Client.ancestors.include?(ScoutApm::Instruments::HTTPInstrumentationPrepend)
        end
      else
        assert_equal false, ::HTTP::Client.ancestors.include?(ScoutApm::Instruments::HTTPInstrumentationPrepend)
        assert_equal false, ::HTTP::Client.ancestors.include?(ScoutApm::Instruments::HTTPInstrumentationPrependV6)
      end
    end
  end
end