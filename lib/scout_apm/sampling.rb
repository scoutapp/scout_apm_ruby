module ScoutApm
  class Sampling

    def initialize(config)
      @global_sample_rate = config.value('sample_rate')
      @sampled_endpoints = individual_sample_to_hash(config.value('sampled_endpoints'))
      @sampled_jobs = individual_sample_to_hash(config.value('sampled_jobs'))
      @ignored_endpoints = config.value('ignored_endpoints').split(',')
      @ignored_jobs = config.value('ignored_jobs').split(',')
      # TODO make this safer/smarter
    end

    def ignored?(transaction)
      # a bunch of logic to determine if a transaction should be ignored
      return
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
  end
end
