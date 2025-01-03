require 'test_helper'

require 'scout_apm/sampling'

class SamplingTest < Minitest::Test
    # tr = ScoutApm::TrackedRequest.new(ScoutApm::AgentContext.new, ScoutApm::FakeStore.new)

    def setup
      @global_sample_config = FakeConfigOverlay.new(
        {
          'sample_rate' => 50,
        }
      )

      @individual_config = FakeConfigOverlay.new(
        {
          'sample_endpoints' => ['/foo:50', '/bar:100'],
          'ignore_endpoints' => ['/baz'],
          'sample_jobs' => ['joba:50'],
          'ignore_jobs' => 'jobb,jobc',
        }
      )
    end

    def test_individual_sample_to_hash
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal({'/foo' => 50, '/bar' => 100}, sampling.individual_sample_to_hash(@individual_config.value('sample_endpoints')))
    end

    def test_uri_ignore
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.ignore_uri?('/baz')
      assert_equal false, sampling.ignore_uri?('/foo')
    end

    def test_uri_sample
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.sample_uri?('/foo')
      assert_equal false, sampling.sample_uri?('/baz')
    end

    def test_job_ignore
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.ignore_job?('jobb')
      assert_equal false, sampling.ignore_job?('joba')
    end

    def test_job_sample
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.sample_job?('joba')
      assert_equal false, sampling.sample_job?('jobb')
    end

    def test_sample
      sampling = ScoutApm::Sampling.new(@global_sample_config)
      sampling.stub(:rand, 1) do
        assert_equal(false, sampling.sample?(50))
      end
      sampling.stub(:rand, 99) do
        assert_equal(true, sampling.sample?(50))
      end
    end
end
