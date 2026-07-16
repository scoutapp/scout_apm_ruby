require 'test_helper'

begin
  require 'grape'
rescue LoadError
  # Grape not available in this gemfile, skip these tests
end

if defined?(::Grape)
  require 'scout_apm/instruments/grape'

  class GrapeTest < Minitest::Test
    # Captured before the instrument is installed. On grape >= 3.3.0 #run is
    # owned by the prepended Grape::Testing::RunBeforeEach module, not the
    # Grape::Endpoint class itself.
    GRAPE_ENDPOINT_OWNS_RUN = ::Grape::Endpoint.instance_method(:run).owner == ::Grape::Endpoint

    class HelloAPI < ::Grape::API
      format :json

      get :hello do
        { message: 'hello' }
      end
    end

    # Install exactly once for the entire test run. Re-running an
    # alias-method install would alias the wrapper onto itself.
    def self.install_instruments
      @install_instruments ||= begin
        context = ScoutApm::AgentContext.new
        instrument_manager = ScoutApm::InstrumentManager.new(context)
        instance = ScoutApm::Instruments::Grape.new(context)
        instance.install(prepend: instrument_manager.prepend_for_instrument?(instance.class))
        instance
      end
    end

    def setup
      @instance = self.class.install_instruments
    end

    def test_installed
      assert @instance.installed?
    end

    # Grape >= 3.3.0 prepends Grape::Testing::RunBeforeEach in front of
    # Grape::Endpoint#run. Building an alias-method chain on top of the
    # prepended method caused infinite recursion (SystemStackError) as soon
    # as any endpoint was called.
    def test_endpoint_runs_without_infinite_recursion
      status, _headers, body = HelloAPI.call(Rack::MockRequest.env_for('/hello'))

      assert_equal 200, status

      body_content = "".dup
      body.each { |chunk| body_content << chunk }
      assert_includes body_content, 'hello'
    end

    def test_installs_using_proper_method
      if GRAPE_ENDPOINT_OWNS_RUN
        # Safe to use the alias-method chain (the default)
        assert_includes ::Grape::Endpoint.ancestors, ScoutApm::Instruments::GrapeEndpointInstruments
        refute_includes ::Grape::Endpoint.ancestors, ScoutApm::Instruments::GrapeEndpointInstrumentsPrepend
      else
        # #run is owned by a module prepended onto Grape::Endpoint, so the
        # instrument must fall back to prepend even though it defaults to
        # the alias-method chain.
        assert_includes ::Grape::Endpoint.ancestors, ScoutApm::Instruments::GrapeEndpointInstrumentsPrepend
      end
    end
  end
end
