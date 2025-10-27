require 'test_helper'

require 'scout_apm/ignored_uris'

class IgnoredUrlsTest < Minitest::Test
  def test_ignores_prefix
    i = ScoutApm::IgnoredUris.new(["/slow", "/health"])
    assert_equal true, i.ignore?("/slow/foo/bar")
    assert_equal true, i.ignore?("/health?leeches=true")
  end

  def test_does_not_ignore_inner
    i = ScoutApm::IgnoredUris.new(["/slow", "/health"])
    assert_equal false, i.ignore?("/users/2/health")
  end

  def test_does_not_ignore_empty_string
    i = ScoutApm::IgnoredUris.new(["", "/admin"])
    assert_equal false, i.ignore?("/users/2/health")
    assert_equal true, i.ignore?("/admin/dashboard")
  end

  def test_ignores_prefix_regex
    i = ScoutApm::IgnoredUris.new(["/slow/\\d+/notifications", "/health"])
    puts i.regex.inspect
    assert_equal true, i.ignore?("/slow/123/notifications")
    assert_equal false, i.ignore?("/slow/abcd/notifications")
    assert_equal true, i.ignore?("/health")
  end
end
