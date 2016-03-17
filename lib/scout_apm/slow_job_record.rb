module ScoutApm
  class SlowJobRecord
    attr_reader :queue_name
    attr_reader :job_name
    attr_reader :total_call_time
    attr_reader :total_exclusive_time
    attr_reader :metrics

    def initialize(queue_name, job_name, total_time, exclusive_time, metrics)
      @queue_name = queue_name
      @job_name = job_name
      @total_time = total_time
      @exclusive_time = exclusive_time
      @metrics = metrics
    end

    def metric_name
      "Job/#{queue_name}/#{job_name}"
    end
  end
end
