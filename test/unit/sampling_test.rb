require 'test_helper'

require 'scout_apm/sampling'

class SamplingTest < Minitest::Test

    def setup
      @global_sample_config = FakeConfigOverlay.new(
        {
          'sample_rate' => 50,
        }
      )

      @individual_config = FakeConfigOverlay.new(
        {
          'sample_endpoints' => ['/foo:50', '/bar/zap:80'],
          'ignore_endpoints' => ['/baz'],
          'sample_jobs' => ['joba:50'],
          'ignore_jobs' => 'jobb,jobc',
        }
      )
    end

    def test_individual_sample_to_hash
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal({'/foo' => 50, '/bar/zap' => 80}, sampling.individual_sample_to_hash(@individual_config.value('sample_endpoints')))
    end

    def test_uri_ignore
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.ignore_uri?('/baz/bap')
      assert_equal false, sampling.ignore_uri?('/foo/far')
    end

    def test_uri_sample
      sampling = ScoutApm::Sampling.new(@individual_config)
      do_sample, rate = sampling.sample_uri?('/foo/far')
      assert_equal true, do_sample
      assert_equal 50, rate

      do_sample, rate = sampling.sample_uri?('/bar')
      assert_equal false, do_sample

      do_sample, rate = sampling.sample_uri?('/baz/bap')
      assert_equal false, do_sample
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
      sampling = ScoutApm::Sampling.new(@individual_config)
      sampling.stub(:rand, 0.01) do
        assert_equal(false, sampling.sample?(50))
      end
      sampling.stub(:rand, 0.99) do
        assert_equal(true, sampling.sample?(50))
      end
    end

    def test_old_ignore
      config = FakeConfigOverlay.new({'ignore' => ['/foo', '/bar']})
      sampling = ScoutApm::Sampling.new(config)
      assert_equal true, sampling.ignore_uri?('/foo')
      assert_equal true, sampling.ignore_uri?('/bar/bap')
      assert_equal false, sampling.ignore_uri?('/baz')
    end

    def test_web_request
      sampling = ScoutApm::Sampling.new(@individual_config)
      # should be ignored
      transaction = FakeTrackedRequest.new_web_request('/baz/bap')
      assert_equal true, sampling.drop_request?(transaction)

      # should be kept
      transaction = FakeTrackedRequest.new_web_request('/faz/bap')
      assert_equal false, sampling.drop_request?(transaction)

      # should be sampled if rand > 50
      transaction = FakeTrackedRequest.new_web_request('/foo/far')
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
      end
    end

    def test_job_request
      sampling = ScoutApm::Sampling.new(@individual_config)
      # should be ignored
      transaction = FakeTrackedRequest.new_job_request('jobb')
      assert_equal true, sampling.drop_request?(transaction)

      # should be kept
      transaction = FakeTrackedRequest.new_job_request('jobz')
      assert_equal false, sampling.drop_request?(transaction)

      # should be sampled if rand > 50
      transaction = FakeTrackedRequest.new_job_request('joba')
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
      end
    end
end
