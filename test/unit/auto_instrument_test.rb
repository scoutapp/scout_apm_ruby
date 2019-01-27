require 'test_helper'

require 'scout_apm/auto_instrument'

class AutoInstrumentTest < Minitest::Test
  def setup
  end

  def source_path(name)
    File.expand_path("auto_instrument/#{name}.rb", __dir__)
  end

  def instrumented_path(name)
    File.expand_path("auto_instrument/instrumented-#{name}.rb", __dir__)
  end

  def instrumented_source(name)
    File.read(instrumented_path(name))
  end

  def test_rails_controller_rewrite
    skip if RUBY_VERSION < "2.3"

    assert_equal instrumented_source("controller"), ::ScoutApm::AutoInstrument::Rails.rewrite(source_path("controller"))
  end
end