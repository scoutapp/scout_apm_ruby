require 'test_helper'
require 'scout_apm/layaway_file'

require 'tmpdir'
class LayawayFileTest < Minitest::Test
  def test_write_and_load
    Dir.mktmpdir do |dir|
      file = ScoutApm::LayawayFile.new(ScoutApm::AgentContext.new, File.join(dir, "layaway"))
      file.write({ "foo" => [1, 2, 3] })

      assert_equal({ "foo" => [1, 2, 3] }, file.load)
    end
  end

  def test_load_does_not_mutate_string_literal
    Dir.mktmpdir do |dir|
      file = ScoutApm::LayawayFile.new(ScoutApm::AgentContext.new, File.join(dir, "layaway"))
      file.write({ "foo" => "bar" })

      assert_equal "", capture_deprecation_warnings { file.load }
    end
  end
end
