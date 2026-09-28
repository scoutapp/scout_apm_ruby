if (ENV["SCOUT_TEST_FEATURES"] || "").include?("instruments")
  require 'test_helper'

  require 'scout_apm/instruments/httpx'

  require 'httpx'
  require 'webmock'

  class HTTPXTest < Minitest::Test
    include WebMock::API

    def setup
      super # clears Thread.current[:scout_request] so a stale request from a
            # prior test can't swallow this test's layers
      WebMock.enable!
      WebMock.disable_net_connect!

      @context = ScoutApm::AgentContext.new
      @recorder = FakeRecorder.new
      ScoutApm::Agent.instance.context.recorder = @recorder
      ScoutApm::Instruments::HTTPX.new(@context).install(prepend: false)
    end

    def teardown
      WebMock.reset!
      WebMock.allow_net_connect!
      WebMock.disable!
      super
    end

    def test_httpx
      stub_request(:get, /news\.ycombinator\.com/).to_return(status: 200, body: "")
      stub_request(:get, /google\.com/).to_return(status: 200, body: "")

      responses = HTTPX.get(
        "https://news.ycombinator.com/news",
        "https://news.ycombinator.com/news?p=2",
        "https://google.com/q=me"
      )

      assert_equal 1, @recorder.requests.length

      assert_recorded(@recorder, "HTTP", "GET", "3 requests")
    end

    def test_httpx_post_request
      stub_request(:post, /httpbin\.org\/post/).to_return(status: 200, body: "")

      HTTPX.post("https://httpbin.org/post", json: { test: "data" })
      assert_recorded(@recorder, "HTTP", "POST", "httpbin.org/post")
    end

    def test_instruments_httpx_error_handling
      # An error response still flows through Session#request, so the layer is
      # started and stopped, and the request is recorded exactly once.
      stub_request(:get, /thisshouldnotexistatall12345\.com/)
        .to_return(status: 500, body: "")

      begin
        HTTPX.get("https://thisshouldnotexistatall12345.com")
      rescue
      end

      assert_equal 1, @recorder.requests.length
    end

    def test_httpx_request_retry
      # A timed-out request is still dispatched through Session#request, so the
      # layer is recorded even though the response errors.
      stub_request(:get, /httpbin\.org\/delay/).to_timeout

      begin
        HTTPX.with(timeout: { connect_timeout: 0.25, request_timeout: 0.25 })
             .get("https://httpbin.org/delay/5")
      rescue
      end
      assert_equal 1, @recorder.requests.length
    end

    def test_multiple_plugins
      stub_request(:get, /news\.ycombinator\.com/).to_return(status: 200, body: "")
      stub_request(:get, "http://httpbin.org/redirect/2")
        .to_return(status: 302, headers: { "Location" => "http://httpbin.org/redirect/1" })
      stub_request(:get, "http://httpbin.org/redirect/1")
        .to_return(status: 302, headers: { "Location" => "http://httpbin.org/get" })
      stub_request(:get, "http://httpbin.org/get").to_return(status: 200, body: "")

      session = HTTPX.plugin(:persistent).plugin(:follow_redirects)

      session.get("https://news.ycombinator.com/news")
      session.get("http://httpbin.org/redirect/2")

      assert_equal 2, @recorder.requests.length, "Expected 2 requests to be recorded"
    end

    private

    def assert_recorded(recorder, type, name, desc = nil)
      req = recorder.requests.first
      assert req, "recorder recorded no layers"
      assert_equal type, req.root_layer.type
      assert_equal name, req.root_layer.name
      if !desc.nil?
        assert req.root_layer.desc.include?(desc),
          "Expected description to include '#{desc}', got '#{req.root_layer.desc}'"
      end
    end
  end
end
