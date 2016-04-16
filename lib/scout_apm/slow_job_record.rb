module ScoutApm
  class SlowJobRecord
    attr_reader :queue_name
    attr_reader :job_name

    # When did this job occur
    attr_reader :time

    # What else interesting did we learn?
    attr_reader :context

    attr_reader :total_time
    attr_reader :exclusive_time
    alias_method :total_call_time, :total_time

    attr_reader :metrics
    attr_reader :mem_delta
    attr_reader :allocations

    def initialize(queue_name, job_name, time, total_time, exclusive_time, context, metrics, mem_delta, allocations)
      @queue_name = queue_name
      @job_name = job_name
      @time = time
      @total_time = total_time
      @exclusive_time = exclusive_time
      @context = context
      @metrics = metrics
      @mem_delta = mem_delta
      @allocations = allocations
      ScoutApm::Agent.instance.logger.debug { "Slow Job [#{metric_name}] - Call Time: #{total_call_time} Mem Delta: #{mem_delta}"}
    end

    def metric_name
      "Job/#{queue_name}/#{job_name}"
    end

  end
end
