module ScoutApm
  class Sampling
    attr_reader :global_sample_rate, :sample_endpoints, :sample_uri_regex, :sample_jobs, :ignore_uri_regex, :ignore_jobs

    def initialize(config)
      @global_sample_rate = config.value('sample_rate')
      # web endpoints matched prefix by regex
      # jobs matched explicitly by name
      @sample_endpoints = individual_sample_to_hash(config.value('sample_endpoints'))
      @ignore_uri_regex = create_uri_regex(config.value('ignore_endpoints'))
      @sample_uri_regex = create_uri_regex(sample_endpoints.keys) if sample_endpoints
      @ignore_jobs = config.value('ignore_jobs').split(',') if config.value('ignore_jobs')
      @sample_jobs = individual_sample_to_hash(config.value('sample_jobs'))
      # TODO make this safer/smarter
    end

    def ignore?(transaction)
      # global sample check
      if global_sample_rate
        return true if sample?(global_sample_rate)
      end

      # job or endpoint?
      # check if ignored _then_ sampled
      if transaction.job?
        job_name = transaction.layer_finder.job.name
        return true if ignore_job?(transaction.job_name)
        if sample_jobs.has_key?(transaction.job_name)
          return true if sample?(sample_jobs[transaction.job_name])
        end
      elsif transaction.web?
        uri = transaction.annotations[:uri]
        return true if ignore_uri?(uri)
        if sample_uri?(uri)
          return true if sample?(uri)
        end
      end

      false # not ignored
    end

    def individual_sample_to_hash(sampling_config)
      return nil if sampling_config.nil?
      # config looks like ['/foo:50','/bar:100']. parse it into hash of string: integer
      sample_hash = {}
      sampling_config.each do |sample|
        path, rate = sample.split(':')
        rate = rate.to_i
        sample_hash[path] = rate
      end
      sample_hash
    end

    def create_uri_regex(prefixes)
      return nil if prefixes.nil?
      regexes = Array(prefixes).
        reject{|prefix| prefix == ""}.
        map {|prefix| %r{\A#{prefix}} }
      Regexp.union(*regexes)
    end

    def ignore_uri?(uri)
      !! ignore_uri_regex.match(uri)
    end

    def sample_uri?(uri)
      !! sample_uri_regex.match(uri)
    end

    def ignore_job?(job_name)
      return false if ignore_jobs.nil?
      ignore_jobs.include?(job_name)
    end

    def sample_job?(job_name)
      return false if sample_jobs.nil?
      sample_jobs.has_key?(job_name)
    end

    def sample?(rate)
      rand * 100 > rate
    end

  end
end
