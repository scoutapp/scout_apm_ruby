require 'test_helper'

class RemoteSecureCompareTest < Minitest::Test
  def test_equal_strings
    assert ScoutApm::Remote.secure_compare("abc123", "abc123")
  end

  def test_different_strings_of_same_length
    refute ScoutApm::Remote.secure_compare("abc123", "abc124")
  end

  def test_different_lengths
    refute ScoutApm::Remote.secure_compare("abc", "abc123")
    refute ScoutApm::Remote.secure_compare("", "abc")
  end
end
