require 'test_helper'

class RemoteRecorderTest < Minitest::Test
  def test_post_sends_token_header
    recorder = ScoutApm::Remote::Recorder.new("127.0.0.1", 7721, Logger.new(StringIO.new), "the-token")

    http = mock
    Net::HTTP.expects(:new).with("127.0.0.1", 7721).returns(http)
    http.expects(:request).with { |req|
      req[ScoutApm::Remote::TOKEN_HEADER] == "the-token" && req.body == "payload"
    }.returns(Net::HTTPOK.new("1.1", "200", "OK"))

    recorder.post("payload")
  end
end
