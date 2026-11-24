require 'test_helper'
require 'socket'

class TestRemoteServer < Minitest::Test
  TOKEN = "a" * 64

  def setup
    @router = stub(:router)
    @server = ScoutApm::Remote::Server.new("127.0.0.1", 0, @router, Logger.new(StringIO.new), TOKEN)

    # Cannot test this if we can't require webrick. Ruby 3 stopped including by default
    skip unless @server.require_webrick
  end

  def teardown
    @server.stop if @server && @server.running?
  end

  def test_start_and_bind
    start_server
    assert @server.running?
  end

  def test_started_as_soon_as_start_returns
    refute @server.started?
    @server.start
    assert @server.started?
  end

  def test_binds_a_free_port_when_given_port_zero
    start_server
    assert_operator @server.port, :>, 0
  end

  def test_accepts_message_with_valid_token
    @router.expects(:handle).with("payload").once
    start_server

    response = post("payload", TOKEN)
    assert_equal "200", response.code
  end

  def test_rejects_message_without_token
    @router.expects(:handle).never
    start_server

    response = post("payload", nil)
    assert_equal "403", response.code
  end

  def test_rejects_message_with_wrong_token
    @router.expects(:handle).never
    start_server

    response = post("payload", "b" * 64)
    assert_equal "403", response.code
  end

  def test_rejects_everything_when_server_has_no_token
    @router.expects(:handle).never
    @server = ScoutApm::Remote::Server.new("127.0.0.1", 0, @router, Logger.new(StringIO.new), nil)
    start_server

    assert_equal "403", post("payload", "").code
  end

  private

  def start_server
    @server.start
    sleep 0.05 # Let the server finish starting
  end

  Response = Struct.new(:code)

  # Raw HTTP over a socket, since other tests may leave Net::HTTP instrumented.
  def post(body, token)
    headers = ["POST /users HTTP/1.1", "Host: 127.0.0.1", "Content-Length: #{body.bytesize}", "Connection: close"]
    headers << "#{ScoutApm::Remote::TOKEN_HEADER}: #{token}" if token
    socket = TCPSocket.new("127.0.0.1", @server.port)
    socket.write(headers.join("\r\n") + "\r\n\r\n" + body)
    Response.new(socket.read[/\AHTTP\/1\.\d (\d{3})/, 1])
  ensure
    socket.close if socket
  end
end
