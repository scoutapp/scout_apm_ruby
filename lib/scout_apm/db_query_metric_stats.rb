module ScoutApm
  class DbQueryMetricStats

    DEFAULT_HISTOGRAM_SIZE = 50

    attr_reader :model_name
    attr_reader :operation
    attr_reader :scope

    attr_reader :call_count
    attr_reader :call_time
    attr_reader :rows_returned

    attr_reader :min_call_time
    attr_reader :max_call_time

    attr_reader :min_rows_returned
    attr_reader :max_rows_returned

    attr_reader :histogram

    def initialize(model_name, operation, scope, call_count, call_time, rows_returned)
      @model_name = model_name
      @operation = operation

      @call_count = call_count

      @call_time = call_time
      @min_call_time = call_time
      @max_call_time = call_time

      @rows_returned = rows_returned
      @min_rows_returned = rows_returned
      @max_rows_returned = rows_returned

      # Should we have a histogram for timing, and one for rows_returned?
      # This histogram is for call_time
      @histogram = NumericHistogram.new(DEFAULT_HISTOGRAM_SIZE)
      @histogram.add(call_time)

      @scope = scope
    end

    # Merge data in this scope. Used in DbQueryMetricSet
    def key
      @key ||= [model_name, operation, scope]
    end

    # Combine data from another DbQueryMetricStats into +self+. Modifies and returns +self+
    def combine!(other)
      return self if other == self

      @call_count += other.call_count
      @rows_returned += other.rows_returned
      @call_time += other.call_time

      @min_call_time = other.min_call_time if @min_call_time.zero? or other.min_call_time < @min_call_time
      @max_call_time = other.max_call_time if other.max_call_time > @max_call_time

      @min_rows_returned = other.min_rows_returned if @min_rows_returned.zero? or other.min_rows_returned < @min_rows_returned
      @max_rows_returned = other.max_rows_returned if other.max_rows_returned > @max_rows_returned

      @histogram.combine!(other.histogram)
      self
    end

    def as_json
      json_attributes = [
        :model_name,
        :operation,
        :scope,

        :call_count,

        :histogram,
        :call_time,
        :max_call_time,
        :min_call_time,

        :max_rows_returned,
        :min_rows_returned,
        :rows_returned,
      ]

      ScoutApm::AttributeArranger.call(self, json_attributes)
    end
  end
end
