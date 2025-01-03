module ScoutApm
  class Sampling
    attr_reader :global_sample_rate, :sample_endpoints, :sample_uri_regex, :sample_jobs, :ignore_uri_regex, :ignore_jobs

    def initialize(config)
      @global_sample_rate = config.value('sample_rate')
      # web endpoints matched prefix by regex
      # jobs matched explicitly by name
      @sample_endpoints = individual_sample_to_hash(config.value('sample_endpoints'))
      @sample_uri_regex = create_uri_regex(sample_endpoints.keys)
      @sample_jobs = individual_sample_to_hash(config.value('sample_jobs'))
      @ignore_uri_regex = create_uri_regex(config.value('ignore_endpoints'))
      @ignore_jobs = config.value('ignore_jobs').split(',')
      # TODO make this safer/smarter
    end

    def ignored?(transaction)
      # global sample check
      if global_sample_rate
        return true if sample?(global_sample_rate)
      end

      # job or endpoint?
      # check ignored _then_ sampled
      if transaction.job?
        job_name = transaction.layer_finder.job.name
        return true if ignore_job?(transaction.job_name)
        if sample_jobs.has_key?(transaction.job_name)
          return true if sample?(sample_jobs[transaction.job_name])
        end
      elsif transaction.web?
        return true if ignore_uri?(transaction.annotations[:uri])
        if sample_uri?(transaction.annotations[:uri])
          return true if sample?(sample_endpoints[transaction.annotations[:uri]])
        end
      end

      false
    end

    private

    def individual_sample_to_hash(sampling_config)
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
      @ignored_jobs.include?(job_name)
    end

    def sample?(rate)
      rand * 100 > rate
    end

  end
end
