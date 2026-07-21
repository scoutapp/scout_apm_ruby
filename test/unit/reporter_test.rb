require 'test_helper'

require 'scout_apm/reporter'

class ReporterTest < Minitest::Test
  def setup
    @context = ScoutApm::AgentContext.new
  end

  # Build a Config with the given overrides taking precedence, but still
  # backed by the real defaults & coercions.
  def config_with(overrides = {})
    overlays = [
      FakeConfigOverlay.new(overrides),
      ScoutApm::Config::ConfigDefaults.new,
      ScoutApm::Config::ConfigNull.new,
    ]
    ScoutApm::Config.new(@context, overlays)
  end

  def reporter_for(overrides = {})
    @context.config = config_with(overrides)
    ScoutApm::Reporter.new(@context, :checkin)
  end

  def https_uri
    URI.parse("https://checkin.scoutapp.com/apps/checkin.scout")
  end

  def test_sets_default_timeouts_on_http_connection
    http = reporter_for.send(:http, https_uri)

    assert_equal 5, http.open_timeout
    assert_equal 5, http.read_timeout
  end

  def test_honors_configured_timeouts
    http = reporter_for('connect_timeout' => 2, 'read_timeout' => 3).send(:http, https_uri)

    assert_equal 2, http.open_timeout
    assert_equal 3, http.read_timeout
  end

  def test_coerces_string_timeouts_from_env
    http = reporter_for('connect_timeout' => "7", 'read_timeout' => "8").send(:http, https_uri)

    assert_equal 7, http.open_timeout
    assert_equal 8, http.read_timeout
  end

  def test_sets_timeouts_for_plain_http_endpoints_too
    http = reporter_for.send(:http, URI.parse("http://checkin.scoutapp.com/apps/checkin.scout"))

    refute http.use_ssl?
    assert_equal 5, http.open_timeout
    assert_equal 5, http.read_timeout
  end
end
