require 'test_helper'

require 'scout_apm/auto_instrument'

class AutoInstrumentTest < Minitest::Test
  def source_path(name)
    File.expand_path("auto_instrument/#{name}.rb", __dir__)
  end

  def instrumented_path(name)
    File.expand_path("auto_instrument/instrumented-#{name}.rb", __dir__)
  end

  def instrumented_source(name)
    File.read(instrumented_path(name))
  end
  
  # Use this to automatically update the test fixtures.
  def update_instrumented_source(name)
    File.write(
      instrumented_path(name),
      ::ScoutApm::AutoInstrument::Rails.rewrite(source_path(name))
    )
  end
  
  def test_rails_controller_rewrite
    assert_equal instrumented_source("controller"), ::ScoutApm::AutoInstrument::Rails.rewrite(source_path("controller"))
    
    # update_instrumented_source("controller")
  end
  
  def test_rescue_from_controller_rewrite
    assert_equal instrumented_source("rescue_from"), ::ScoutApm::AutoInstrument::Rails.rewrite(source_path("rescue_from"))
    
    # update_instrumented_source("rescue_from")
  end
end if defined? ScoutApm::AutoInstrument