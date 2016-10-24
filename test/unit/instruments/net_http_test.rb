require 'test_helper'

require 'scout_apm/instruments/net_http'

require 'addressable'

class NetHttpTest < Minitest::Test
  def setup
    ScoutApm::Instruments::NetHttp.new.install
  end

  def test_request_scout_description_for_uri
    req = Net::HTTP::Get.new(URI('http://example.org/here'))
    assert_equal '/here', Net::HTTP.new('').request_scout_description(req)
  end

  def test_request_scout_description_for_addressable
    req = Net::HTTP::Get.new(Addressable::URI.parse('http://example.org/here'))
    assert_equal '/here', Net::HTTP.new('').request_scout_description(req)
  end
end
