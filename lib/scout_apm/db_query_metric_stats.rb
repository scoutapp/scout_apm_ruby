module ScoutApm
  class DbQueryMetricStats

    attr_accessor :model_name
    attr_accessor :operation
    attr_accessor :call_count
    attr_accessor :call_time
    attr_accessor :rows_returned

    attr_accessor :min_call_time
    attr_accessor :max_call_time
    attr_accessor :total_call_time

    def initialize(model_name, operation, call_count, call_time, rows_returned)
      @model_name = model_name
      @operation = operation

      @call_count = call_count
      @call_time = call_time
      @rows_returned = rows_returned

      @min_call_time = call_time
      @max_call_time = call_time
      @total_call_time = call_time
    end

    def key
      @key ||= "#{model_name}##{operation}"
    end

    def combine!(other)
      return self if other == self

      self.call_count += other.call_count
      self.rows_returned += self.rows_returned
      self.total_call_time += other.total_call_time
      self.min_call_time = other.min_call_time if self.min_call_time.zero? or other.min_call_time < self.min_call_time
      self.max_call_time = other.max_call_time if other.max_call_time > self.max_call_time
      self
    end

    # To avoid conflicts with different JSON libaries handle JSON ourselves.
    # Time-based metrics are converted to milliseconds from seconds.
    def to_json(*a)
       %Q[{"call_count":#{call_count},"total_call_time":#{total_call_time*1000},"min_call_time":#{min_call_time*1000},"max_call_time":#{max_call_time*1000},"rows_returned":#{rows_returned}}]
    end

    def as_json
      json_attributes = [:call_count, :total_call_time, :min_call_time, :max_call_time, :rows_returned]
      # uri, context
      ScoutApm::AttributeArranger.call(self, json_attributes)
    end
  end
end
