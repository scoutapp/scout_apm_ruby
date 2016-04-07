module ScoutApm
  class Layer
    # Type: a general name for the kind of thing being tracked.
    #   Examples: "Middleware", "ActiveRecord", "Controller", "View"
    #
    attr_reader :type

    # Name: a more specific name of this single item
    #   Examples: "Rack::Cache", "User#find", "users/index", "users/index.html.erb"
    attr_reader :name

    # An array of children layers, in call order.
    # For instance, if we are in a middleware, there will likely be only a single
    # child, which is another middleware.  In a Controller, we may have a handful
    # of children: [ActiveRecord, ActiveRecord, View, HTTP Call].
    #
    # This useful to get actual time spent in this layer vs. children time
    attr_reader :children

    # Time objects recording the start & stop times of this layer
    attr_reader :start_time, :stop_time

    # The description of this layer.  Will contain additional details specific to the type of layer.
    # For an ActiveRecord metric, it will contain the SQL run
    # For an outoing HTTP call, it will contain the remote URL accessed
    # Leave blank if there is nothing to note
    attr_reader :desc

    # If this layer took longer than a fixed amount of time, store the
    # backtrace of where it occurred.
    attr_reader :backtrace

    BACKTRACE_CALLER_LIMIT = 30 # maximum number of lines to send thru for backtrace analysis

    def initialize(type, name, start_time = Time.now)
      @type = type
      @name = name
      @start_time = start_time
      @children = [] # In order of calls
      @desc = nil
    end

    def add_child(child)
      @children << child
    end

    def record_stop_time!(stop_time = Time.now)
      @stop_time = stop_time
    end

    def desc=(desc)
      @desc = desc
    end

    def subscopable!
      @subscopable = true
    end

    def subscopable?
      @subscopable
    end

    # This is the old style name. This function is used for now, but should be
    # removed, and the new type & name split should be enforced through the
    # app.
    def legacy_metric_name
      "#{type}/#{name}"
    end

    def capture_backtrace!
      @backtrace = caller_array
    end

    # In Ruby 2.0+, we can pass the range directly to the caller to reduce the memory footprint.
    def caller_array
      # omits the first several callers which are in the ScoutAPM stack.
      if ScoutApm::Environment.instance.ruby_2?
        caller(3...BACKTRACE_CALLER_LIMIT)
      else
        caller[3...BACKTRACE_CALLER_LIMIT]
      end
    end

    ######################################
    # Debugging Helpers
    ######################################

    # May not be safe to call in every rails app, relies on Time#iso8601
    def to_s
      name_clause = "#{type}/#{name}"

      total_string = total_call_time == 0 ? nil : "Total: #{total_call_time}"
      self_string = total_exclusive_time == 0 ? nil : "Self: #{total_exclusive_time}"
      timing_string = [total_string, self_string].compact.join(", ")

      time_clause = "(Start: #{start_time.iso8601} / Stop: #{stop_time.try(:iso8601)} [#{timing_string}])"
      desc_clause = "Description: #{desc.inspect}"
      children_clause = "Children: #{children.length}"

      "<Layer: #{name_clause} #{time_clause} #{desc_clause} #{children_clause}>"
    end

    ######################################
    # Time Calculations
    ######################################

    def total_call_time
      if stop_time
        stop_time - start_time
      else
        # Shouldn't have called this yet. Return 0
        0
      end
    end

    def total_exclusive_time
      total_call_time - child_time
    end

    def child_time
      children.
        map { |child| child.total_call_time }.
        inject(0) { |sum, time| sum + time }
    end
  end
end
