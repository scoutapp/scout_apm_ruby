if (ENV["SCOUT_TEST_FEATURES"] || "").include?("instruments")

  require 'test_helper'

  require 'grape'
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

    # Either instrumentation method is valid: alias_method is the default,
    # prepend is used when configured (`use_prepend`/`prepend_instruments`)
    # or when the instrument falls back to it for safety.
    def test_installs_using_prepend_or_alias_method
      assert prepended? || aliased?, "expected Grape::Endpoint to be instrumented via prepend or alias_method"

      unless GRAPE_ENDPOINT_OWNS_RUN
        # On grape >= 3.3.0 #run is owned by a module prepended onto
        # Grape::Endpoint, where an alias-method chain would recurse, so the
        # instrument must have used prepend even though alias_method is the
        # default.
        assert prepended?, "grape >= 3.3.0 requires the prepend instrumentation method"
        refute aliased?, "the alias-method chain must not be installed over a prepended #run"
      end
    end

    private

    def prepended?
      ::Grape::Endpoint.ancestors.include?(ScoutApm::Instruments::GrapeEndpointInstrumentsPrepend)
    end

    def aliased?
      ::Grape::Endpoint.method_defined?(:run_without_scout_instruments) ||
        ::Grape::Endpoint.private_method_defined?(:run_without_scout_instruments)
    end
  end
end
