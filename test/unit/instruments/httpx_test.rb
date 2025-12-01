if (ENV["SCOUT_TEST_FEATURES"] || "").include?("instruments")
  require 'test_helper'

  require 'scout_apm/instruments/httpx'

  require 'httpx'

  class HTTPXTest < Minitest::Test
    def setup
      @context = ScoutApm::AgentContext.new
      @recorder = FakeRecorder.new
      ScoutApm::Agent.instance.context.recorder = @recorder
      ScoutApm::Instruments::HTTPX.new(@context).install(prepend: false)
    end


    def test_httpx
      responses = HTTPX.get(
        "https://news.ycombinator.com/news",
        "https://news.ycombinator.com/news?p=2",
        "https://google.com/q=me"
      )

      assert_equal 1, @recorder.requests.length

      assert_recorded(@recorder, "HTTP", "GET", "3 requests")
    end

    def test_httpx_post_request
      HTTPX.post("https://httpbin.org/post", json: { test: "data" })
      assert_recorded(@recorder, "HTTP", "POST", "httpbin.org/post")
    end

    def test_instruments_httpx_error_handling
      begin
        HTTPX.get("https://thisshouldnotexistatall12345.com")
      rescue
      end

      assert_equal 1, @recorder.requests.length
    end

    def test_httpx_request_retry
      begin
        HTTPX.with(timeout: { connect_timeout: 0.25, request_timeout: 0.25 })
             .get("https://httpbin.org/delay/5")
      rescue
      end
      assert_equal 1, @recorder.requests.length
    end

    def test_multiple_plugins
      session = HTTPX.plugin(:persistent).plugin(:follow_redirects)

      session.get("https://news.ycombinator.com/news")
      begin
        session.get("http://httpbin.org/redirect/2")
      rescue
        skip "httpbin.org not available"
      end

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
