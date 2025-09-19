module ScoutApm
  class Sampling
    attr_reader :global_sample_rate, :sample_endpoints, :sample_uri_regex, :sample_jobs, :ignore_uri_regex, :ignore_jobs

    def initialize(config)
      @global_sample_rate = config.value('sample_rate')
      # web endpoints matched prefix by regex
      # jobs matched explicitly by name

      # for now still support old config key ('ignore') for backwards compatibility
      @ignore_endpoints = config.value_present?('ignore') ? config.value('ignore') : config.value('ignore_endpoints')
      @sample_endpoints = individual_sample_to_hash(config.value('sample_endpoints'))
      @endpoint_sample_rate = config.value('endpoint_sample_rate')

      @ignore_jobs = config.value('ignore_jobs')
      @sample_jobs = individual_sample_to_hash(config.value('sample_jobs'))
      @job_sample_rate = config.value('job_sample_rate')

      log_string = "Sampling initialized with config: "
      log_string += "global_sample_rate: #{@global_sample_rate.inspect}, "
      log_string += "endpoint_sample_rate: #{@endpoint_sample_rate.inspect}, "
      log_string += "sample_endpoints: #{@sample_endpoints.inspect}, "
      log_string += "ignore_endpoints: #{@ignore_endpoints.inspect}, "
      log_string += "job_sample_rate: #{@job_sample_rate.inspect}, "
      log_string += "sample_jobs: #{@sample_jobs.inspect}, "
      log_string += "ignore_jobs: #{@ignore_jobs.inspect}"
      logger.info(log_string)
    end

    def drop_request?(transaction)
      # Individual endpoint/job sampling takes precedence over ignoring.
      # Individual endpoint/job sample rate always takes precedence over general endpoint/job rate.
      # General endpoint/job rate always takes precedence over global sample rate
      if transaction.job?
        job_name = transaction.layer_finder.job.name
        rate = job_sample_rate(job_name)
        return downsample?(rate) unless rate.nil?
        return true if ignore_job?(job_name)
        return downsample?(@job_sample_rate) unless @job_sample_rate.nil?
      elsif transaction.web?
        uri = transaction.annotations[:uri]
        rate = web_sample_rate(uri)
        return downsample?(rate) unless rate.nil?
        return true if ignore_uri?(uri)
        return downsample?(@endpoint_sample_rate) unless @endpoint_sample_rate.nil?
      end

      # global sample check
      if @global_sample_rate
        return downsample?(@global_sample_rate)
      end

      false # don't drop the request
    end

    def individual_sample_to_hash(sampling_config)
      return nil if sampling_config.blank?
      # config looks like ['/foo:50','/bar:100']. parse it into hash of string: integer
      sample_hash = {}
      sampling_config.each do |sample|
        path, _, rate = sample.rpartition(':')
        sample_hash[path] = coerce_to_rate(rate)
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

    def web_sample_rate(uri)
      return nil if @sample_endpoints.blank?
      @sample_endpoints.each do |prefix, rate|
        return rate if uri.start_with?(prefix)
      end
      nil
    end

    def ignore_job?(job_name)
      return false if @ignore_jobs.blank?
      @ignore_jobs.include?(job_name)
    end

    def job_sample_rate(job_name)
      return nil if @sample_jobs.blank?
      @sample_jobs.fetch(job_name, nil)
    end

    def downsample?(rate)
      # Should we drop this request based on the sample rate?
      rand > rate
    end

    private

    def logger
      ScoutApm::Agent.instance.logger
    end

    def coerce_to_rate(val)
      # Analogous to Config::SampleRateCoercion
      v = val.to_f
      # Anything above 1 is assumed a percentage for backwards compat, so convert to a decimal
      if v >= 1
        v = v / 100
      end
      if v < 0 || v > 1
        logger.warn("Sample rates must be between 0 and 1. You passed in #{val.inspect}, which we interpreted as #{v}. Clamping.")
        v = v.clamp(0, 1)
      end
      v
    end
  end
end
