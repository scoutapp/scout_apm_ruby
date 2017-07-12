require 'test_helper'

class TestRemoteServer < Minitest::Test
  def test_start_and_bind
    server = ScoutApm::Remote::Server.new({}, Logger.new(STDOUT), port: 9982)

    server.start
    sleep 0.01 # Let the server finish starting. The assert should instead allow a time
    assert server.running?
  end
end
