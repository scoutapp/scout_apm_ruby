require 'test_helper'

require 'scout_apm/sampling'

class SamplingTest < Minitest::Test

    def setup
      @global_sample_config = FakeConfigOverlay.new(
        {
          'sample_rate' => 80,
        }
      )

      @individual_config = FakeConfigOverlay.new(
        {
          'sample_endpoints' => ['/foo/bar:100', '/foo:50', '/bar/zap:80'],
          'ignore_endpoints' => ['/baz'],
          'sample_jobs' => ['joba:50'],
          'ignore_jobs' => 'jobb,jobc',
        }
      )
    end

    def test_individual_sample_to_hash
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal({'/foo/bar' => 100, '/foo' => 50, '/bar/zap' => 80}, sampling.individual_sample_to_hash(@individual_config.value('sample_endpoints')))

      sampling = ScoutApm::Sampling.new(@global_sample_config)
      assert_equal nil, sampling.individual_sample_to_hash(@global_sample_config.value('sample_endpoints'))
    end

    def test_uri_ignore
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.ignore_uri?('/baz/bap')
      assert_equal false, sampling.ignore_uri?('/foo/far')
    end

    def test_uri_sample
      sampling = ScoutApm::Sampling.new(@individual_config)
      rate = sampling.web_sample_rate('/foo/far')
      assert_equal 50, rate

      rate = sampling.web_sample_rate('/bar')
      assert_equal nil, rate

      rate = sampling.web_sample_rate('/baz/bap')
      assert_equal nil, rate

      rate = sampling.web_sample_rate('/foo/bar/baz')
      assert_equal 100, rate
    end

    def test_job_ignore
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal true, sampling.ignore_job?('jobb')
      assert_equal false, sampling.ignore_job?('joba')
    end

    def test_job_sample
      sampling = ScoutApm::Sampling.new(@individual_config)
      assert_equal 50, sampling.job_sample_rate('joba')
      assert_equal nil, sampling.job_sample_rate('jobb')
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

    def test_web_request_individual_sampling
      sampling = ScoutApm::Sampling.new(@individual_config)

      # should be ignored
      transaction = FakeTrackedRequest.new_web_request('/baz/bap')
      assert_equal true, sampling.drop_request?(transaction)

      # should be kept
      transaction = FakeTrackedRequest.new_web_request('/faz/bap')
      assert_equal false, sampling.drop_request?(transaction)

      transaction = FakeTrackedRequest.new_web_request('/foo/far')
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      # passes individual sample but caught by global rate
      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
      end
    end

    def test_web_reqeust_general_sampling
      config = FakeConfigOverlay.new(@individual_config.values.merge({'endpoint_sample_rate' => 80}))
      sampling = ScoutApm::Sampling.new(config)

      transaction = FakeTrackedRequest.new_web_request('/foo/far')
      transaction2 = FakeTrackedRequest.new_web_request('/ooo/oar')
      # /foo/far sampled at 50 specifically, /ooo/oar caught by general endpoint rate of 80
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
        assert_equal false, sampling.drop_request?(transaction2)
      end

      sampling.stub(:rand, 0.70) do
        assert_equal true, sampling.drop_request?(transaction)
        assert_equal false, sampling.drop_request?(transaction2)
      end

      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
        assert_equal true, sampling.drop_request?(transaction2)
      end
    end

    def test_web_request_with_global_sampling
      config = FakeConfigOverlay.new(@individual_config.values.merge({'sample_rate' => 20}))
      sampling = ScoutApm::Sampling.new(config)

      # caught by individual rate
      transaction = FakeTrackedRequest.new_web_request('/foo/far')
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      # passes individual rate (50) but caught by global rate (20)
      sampling.stub(:rand, 0.30) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      # passes individual rate
      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
      end

    end

    def test_job_request_individual_sampling
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

    def test_job_general_sampling
      config = FakeConfigOverlay.new(@individual_config.values.merge({'job_sample_rate' => 80}))
      sampling = ScoutApm::Sampling.new(config)

      transaction = FakeTrackedRequest.new_job_request('joba')
      transaction2 = FakeTrackedRequest.new_job_request('jobz')
      # joba sampled at 50 specifically, jobz caught by general job rate of 80
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
        assert_equal false, sampling.drop_request?(transaction2)
      end

      sampling.stub(:rand, 0.70) do
        assert_equal true, sampling.drop_request?(transaction)
        assert_equal false, sampling.drop_request?(transaction2)
      end

      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
        assert_equal true, sampling.drop_request?(transaction2)
      end
    end

    def test_job_request_global_sampling
      config = FakeConfigOverlay.new(@individual_config.values.merge({'sample_rate' => 20}))
      sampling = ScoutApm::Sampling.new(config)

      # caught by individual rate
      transaction = FakeTrackedRequest.new_job_request('joba')
      sampling.stub(:rand, 0.01) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      # passes individual rate (50) but caught by global rate (20)
      sampling.stub(:rand, 0.30) do
        assert_equal false, sampling.drop_request?(transaction)
      end

      # passes individual rate
      sampling.stub(:rand, 0.99) do
        assert_equal true, sampling.drop_request?(transaction)
      end
    end
end
