module ScoutApm
  class PeriodicWork
    attr_reader :context

    def initialize(context)
      @context = context
      @reporting = ScoutApm::Reporting.new(context)
    end

    # Expected to be called many times over the life of the agent
    def run
      ScoutApm::Debug.instance.call_periodic_hooks
      @reporting.process_metrics
      clean_old_percentiles
    end

    private

    # XXX: Move logic into a RequestHistogramsByTime class that can keep the timeout logic in it
    def clean_old_percentiles
      context.
        request_histograms_by_time.
        keys.
        select {|timestamp| timestamp.age_in_seconds > 60 * 10 }.
        each {|old_timestamp| context.request_histograms_by_time.delete(old_timestamp) }
    end
  end
end
