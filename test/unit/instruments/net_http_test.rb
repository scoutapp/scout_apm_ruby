require 'test_helper'

require 'scout_apm/instruments/net_http'

require 'addressable/uri'

class NetHttpTest < Minitest::Test
  def setup
    @context = ScoutApm::AgentContext.new
    ScoutApm::Instruments::NetHttp.new(@context).install
  end

  def test_request_scout_description_for_uri
    if RUBY_VERSION <= '1.9.3'
      req = Net::HTTP::Get.new('/here')
    else
      req = Net::HTTP::Get.new(URI('http://example.org/here'))
    end

    assert_equal '/here', Net::HTTP.new('').request_scout_description(req)
  end

  def test_request_scout_description_for_addressable
    req = Net::HTTP::Get.new(Addressable::URI.parse('http://example.org/here'))
    assert_equal '/here', Net::HTTP.new('').request_scout_description(req)
  end
end
