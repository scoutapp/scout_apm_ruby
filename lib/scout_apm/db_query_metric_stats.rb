module ScoutApm
  class DbQueryMetricStats

    DEFAULT_HISTOGRAM_SIZE = 50

    attr_accessor :model_name
    attr_accessor :operation
    attr_accessor :call_count
    attr_accessor :call_time
    attr_accessor :rows_returned

    attr_accessor :min_call_time
    attr_accessor :max_call_time

    attr_accessor :min_rows_returned
    attr_accessor :max_rows_returned

    attr_accessor :histogram

    def initialize(model_name, operation, call_count, call_time, rows_returned)
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
    end

    # `User#find`, `Org#create` etc.
    def key
      @key ||= "#{model_name}##{operation}"
    end

    # Combine data from another DbQueryMetricStats into +self+. Modifies and returns +self+
    def combine!(other)
      return self if other == self

      self.call_count += other.call_count
      self.rows_returned += other.rows_returned
      self.call_time += other.call_time

      self.min_call_time = other.min_call_time if self.min_call_time.zero? or other.min_call_time < self.min_call_time
      self.max_call_time = other.max_call_time if other.max_call_time > self.max_call_time

      self.min_rows_returned = other.min_rows_returned if self.min_rows_returned.zero? or other.min_rows_returned < self.min_rows_returned
      self.max_rows_returned = other.max_rows_returned if other.max_rows_returned > self.max_rows_returned

      self.histogram.combine!(other.histogram)
      self
    end

    def as_json
      json_attributes = [
        :model_name,
        :operation,

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
