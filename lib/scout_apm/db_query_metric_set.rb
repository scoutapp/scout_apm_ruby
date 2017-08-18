module ScoutApm
  class DbQueryMetricSet
    attr_reader :metrics

    def initialize
      @metrics = Hash.new
    end

    def lookup(other)
      metrics[other.key] ||= other
    end

    def combine!(other)
      lookup(other).combine!(other)
    end
  end
end
