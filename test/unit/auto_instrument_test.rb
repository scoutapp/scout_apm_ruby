require 'test_helper'

class AutoInstrumentTest < Minitest::Test
  def setup
    require 'scout_apm/auto_instrument'
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
    assert_equal instrumented_source("controller"), ::ScoutApm::AutoInstrument::Rails.rewrite(source_path("controller"))
  end
end if defined? ScoutApm::AutoInstrument