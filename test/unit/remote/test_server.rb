require 'test_helper'

class TestRemoteServer < Minitest::Test
  def test_start_and_bind
    bind = "127.0.0.1"
    port = 8938
    router = stub(:router)
    logger_io = StringIO.new
    server = ScoutApm::Remote::Server.new(bind, port, router, Logger.new(logger_io))

    server.start
    sleep 0.01 # Let the server finish starting. The assert should instead allow a time
    assert server.running?
  end
end
