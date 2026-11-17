require 'test_helper'

class ReporterTest < Minitest::Test
  FakeContext = Struct.new(:config)

  def test_http_does_not_set_ca_file_when_default_is_nil
    config = FakeConfigOverlay.new('ssl_cert_file' => nil)
    reporter = ScoutApm::Reporter.new(FakeContext.new(config), :checkin)
    Net::HTTP.any_instance.expects(:ca_file=).never

    http = reporter.send(:http, URI.parse('https://example.com'))

    assert http.use_ssl?
    assert_equal ScoutApm::Reporter::VERIFY_MODE, http.verify_mode
  end

  def test_http_uses_explicit_ca_file
    config = FakeConfigOverlay.new('ssl_cert_file' => '/tmp/custom-ca.pem')
    reporter = ScoutApm::Reporter.new(FakeContext.new(config), :checkin)
    Net::HTTP.any_instance.expects(:ca_file=).with('/tmp/custom-ca.pem')

    reporter.send(:http, URI.parse('https://example.com'))
  end
end
