require 'test_helper'

require 'scout_apm/auto_instrument'

class AutoInstrumentTest < Minitest::Test
  def source_path(name)
    File.expand_path("auto_instrument/#{name}.rb", __dir__)
  end

  def instrumented_path(name)
    File.expand_path("auto_instrument/#{name}-instrumented.rb", __dir__)
  end

  def instrumented_source(name)
    File.read(instrumented_path(name))
  end

  # Autoinstruments adds a backtrace to each created layer. This is the full path to the
  # test controller.rb file, which will be different on different environments.
  # This normalizes backtraces across environments.
  def normalize_backtrace(string)
    string.gsub(/\[".+auto_instrument\/controller.rb:.+"\]/,'["BACKTRACE"]')
  end

  # Use this to automatically update the test fixtures.
  def update_instrumented_source(name)
    File.write(
      instrumented_path(name),
      normalize_backtrace(::ScoutApm::AutoInstrument::Rails.rewrite(source_path(name)))
    )
  end

  def test_controller_rewrite
    assert_equal instrumented_source("controller"),
      normalize_backtrace(::ScoutApm::AutoInstrument::Rails.rewrite(source_path("controller")))

    # update_instrumented_source("controller")
  end

  def test_rescue_from_rewrite
    assert_equal instrumented_source("rescue_from"),
      normalize_backtrace(::ScoutApm::AutoInstrument::Rails.rewrite(source_path("rescue_from")))

    # update_instrumented_source("rescue_from")
  end
end if defined? ScoutApm::AutoInstrument
