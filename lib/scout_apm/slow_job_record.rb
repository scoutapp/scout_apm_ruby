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

    attr_reader :score

    def initialize(queue_name, job_name, time, total_time, exclusive_time, context, metrics, score)
      @queue_name = queue_name
      @job_name = job_name
      @time = time
      @total_time = total_time
      @exclusive_time = exclusive_time
      @context = context
      @metrics = metrics
      @score = score
    end

    def metric_name
      "Job/#{queue_name}/#{job_name}"
    end

    ########################
    # Scorable interface
    #
    # Needed so we can merge ScoredItemSet instances
    def call
      self
    end

    def name
      metric_name
    end

    def score
      @score
    end

  end
end
