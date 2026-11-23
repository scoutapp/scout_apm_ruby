require 'test_helper'

require 'scout_apm/instant/middleware'

class InstantMiddlewareTest < Minitest::Test
  HTML = "<html><head></head><body><p>hi</p></body></html>".freeze

  def setup
    ScoutApm::Instant::DevTraceResponseManipulator.any_instance.stubs(:dev_trace_disabled?).returns(false)
    ScoutApm::Instant::DevTraceResponseManipulator.any_instance.stubs(:tracked_request).returns(stub(:ignoring_request? => false))
    ScoutApm::Instant::DevTraceResponseManipulator.any_instance.stubs(:trace).returns(Object.new)
    ScoutApm::Instant::DevTraceResponseManipulator.any_instance.stubs(:payload).returns("{}")
  end

  # Hotwire::Spark rewrites the HTML and returns a plain Array body.
  def test_injects_dev_trace_into_html_array_body
    headers = { "Content-Type" => "text/html; charset=utf-8", "Content-Length" => HTML.bytesize.to_s }
    status, new_headers, body = manipulate([200, headers, [HTML.dup]])

    assert_equal 200, status
    assert_includes body.join, "scout_instant.js"
    assert_includes body.join, "scoutInstantPageTrace"
    refute new_headers.key?("Content-Length")
  end

  def test_handles_lowercase_rack3_headers
    headers = { "content-type" => "text/html", "content-length" => HTML.bytesize.to_s }
    _status, new_headers, body = manipulate([200, headers, [HTML.dup]])

    assert_includes body.join, "scout_instant.js"
    refute new_headers.key?("content-length")
  end

  def test_leaves_non_html_array_body_alone
    response = [200, { "Content-Type" => "text/css" }, ["body { color: red }"]]
    assert_equal response, manipulate(response)
  end

  def test_leaves_file_body_alone
    file_body = Object.new
    def file_body.each; yield "x"; end
    response = [200, { "Content-Type" => "text/html" }, file_body]
    assert_same file_body, manipulate(response)[2]
  end

  private

  def manipulate(response)
    env = { "PATH_INFO" => "/" }
    ScoutApm::Instant::DevTraceResponseManipulator.new(env, response).call
  end
end
