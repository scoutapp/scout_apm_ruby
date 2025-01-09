module ScoutApm
  class Sampling
    attr_reader :global_sample_rate, :sample_endpoints, :sample_uri_regex, :sample_jobs, :ignore_uri_regex, :ignore_jobs

    def initialize(config)
      @global_sample_rate = config.value('sample_rate')
      # web endpoints matched prefix by regex
      # jobs matched explicitly by name

      # for now still support old config key ('ignore') for backwards compatibility
      @ignore_endpoints = config.value('ignore').present? ? config.value('ignore') : config.value('ignore_endpoints')

      @sample_endpoints = individual_sample_to_hash(config.value('sample_endpoints'))

      @ignore_jobs = config.value('ignore_jobs')
      @sample_jobs = individual_sample_to_hash(config.value('sample_jobs'))

      logger.info("Sampling Initialized: global_sample_rate: #{global_sample_rate}, sample_endpoints: #{sample_endpoints}, ignore_uri_regex: #{ignore_uri_regex}, sample_uri_regex: #{sample_uri_regex}, ignore_jobs: #{ignore_jobs}, sample_jobs: #{sample_jobs}")
    end

    def drop_request?(transaction)
      # global sample check
      if global_sample_rate
        return true if sample?(global_sample_rate)
      end

      # job or endpoint?
      # check if ignored _then_ sampled
      if transaction.job?
        job_name = transaction.layer_finder.job.name
        return true if ignore_job?(job_name)
        if sample_job?(job_name)
          return true if sample?(sample_jobs[job_name])
        end
      elsif transaction.web?
        uri = transaction.annotations[:uri]
        return true if ignore_uri?(uri)
        do_sample, rate = sample_uri?(uri)
        if do_sample
          return true if sample?(rate)
        end
      end

      false # not ignored
    end

    def individual_sample_to_hash(sampling_config)
      return nil if sampling_config.blank?
      # config looks like ['/foo:50','/bar:100']. parse it into hash of string: integer
      sample_hash = {}
      sampling_config.each do |sample|
        path, rate = sample.split(':')
        sample_hash[path] = rate.to_i
      end
      sample_hash
    end

    def ignore_uri?(uri)
      return false if @ignore_endpoints.blank?
      @ignore_endpoints.each do |prefix|
        return true if uri.start_with?(prefix)
      end
      false
    end

    def sample_uri?(uri)
      return false if @sample_endpoints.blank?
      @sample_endpoints.each do |prefix, rate|
        return true, rate if uri.start_with?(prefix)
      end
      return false, nil
    end

    def ignore_job?(job_name)
      return false if ignore_jobs.blank?
      ignore_jobs.include?(job_name)
    end

    def sample_job?(job_name)
      return false if sample_jobs.blank?
      sample_jobs.has_key?(job_name)
    end

    def sample?(rate)
      rand * 100 > rate
    end

    private

    def logger
      ScoutApm::Agent.instance.logger
    end

  end
end
