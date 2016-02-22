# Records details about all runs of a given job.
#
# Contains:
#   Queue Name
#   Job Name
#   Job Runtime - histogram
#   Metrics collected during the run (Database, HTTP, View, etc)
module ScoutApm
  class JobRecord
    attr_reader :queue_name
    attr_reader :job_name
    attr_reader :runtime

    # Metrics includes error count(?)
    attr_reader :metrics

    def initialize(queue_name, job_name, total_time, metrics)
      @queue_name = queue_name
      @job_name = job_name
      @runtime = NumericHistogram.new(50)
      @runtime.add(total_time)
      @metrics = MetricSet.new
      @metrics.absorb_all(metrics)
    end

    # Modifies self and returns self, after merging in `other`.
    def combine!(other)
      same_job = queue_name == other.queue_name && job_name == other.job_name
      raise "Mismatched Merge of Background Job" unless same_job

      @metrics = metrics.combine!(other.metrics)
      @runtime.combine!(other.runtime)

      self
    end

    def histogram
      {
        "0" => runtime.quantile(0),
        "50" => runtime.quantile(50),
        "95" => runtime.quantile(95),
        "100" => runtime.quantile(100),
        "avg" => runtime.mean,
      }
    end

    def run_count
      runtime.total
    end
  end
end

