require 'test_helper'
require 'scout_apm/utils/unique_id'

class UniqueIdTest < Minitest::Test
  UniqueId = ScoutApm::Utils::UniqueId

  def test_simple
    id = UniqueId.simple
    assert_match(/\A[a-z]{16}\z/, id)
    assert_match(/\A[a-z]{4}\z/, UniqueId.simple(4))
  end

  def test_simple_does_not_mutate_string_literal
    assert_equal "", capture_deprecation_warnings { UniqueId.simple }
  end
end
