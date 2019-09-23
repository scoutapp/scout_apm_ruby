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
      log_layer_histograms
    end

    private

    def log_layer_histograms
      # Ex key/value -
      # "/Users/dlite/projects/scout/apm/app/controllers/application_controller.rb"=>[[0.0, 689], [1.0, 16]]
      hists = context.auto_instruments_layer_histograms.as_json
      hists_summary = hists.map { |k,v|
        [
          k,
          {:total => total=v.map(&:last).inject(:+), :significant => (v.last.last/total.to_f).round(2)}
        ]
      }.to_h
      context.logger.debug("AutoInstrument Significant Layer Histograms: #{hists_summary.pretty_inspect}")
    end

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
