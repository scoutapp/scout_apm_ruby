module ScoutApm
  class Layer
    # Type: a general name for the kind of thing being tracked.
    #   Examples: "Middleware", "ActiveRecord", "Controller", "View"
    #
    attr_reader :type

    # Name: a more specific name of this single item
    #   Examples: "Rack::Cache", "User#find", "users/index", "users/index.html.erb"
    #
    # Accessor, so we can update a layer if multiple pieces of instrumentation work
    #   together at different layers to fill in the full data. See the ActiveRecord
    #   instrumentation for an example of how this is useful
    attr_accessor :name

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

    # As we go through a part of a request, instrumentation can store additional data
    # Known Keys:
    #   :record_count - The number of rows returned by an AR query (From notification instantiation.active_record)
    #   :class_name   - The ActiveRecord class name (From notification instantiation.active_record)
    attr_reader :annotations

    # Captured backtraces from ScoutProf. This is distinct from the backtrace
    # attribute, which gets the ruby backtrace of any given layer. StackProf
    # focuses on Controller layers, and requires a native extension and a
    # reasonably recent Ruby.
    attr_reader :trace_index
    attr_reader :stack_index
    attr_reader :traces

    BACKTRACE_CALLER_LIMIT = 50 # maximum number of lines to send thru for backtrace analysis

    def initialize(type, name, start_time = Time.now)
      @type = type
      @name = name
      @annotations = {}
      @start_time = start_time
      @allocations_start = ScoutApm::Instruments::Allocations.count
      @allocations_stop = 0
      @children = [] # In order of calls
      @desc = nil

      @traces = ScoutApm::TraceSet.new
      @stack_index = stack_index
      @trace_index = ScoutApm::Instruments::Stacks.current_trace_index
      ScoutApm::Instruments::Stacks.update_indexes(@stack_index, @trace_index)
    end

    def add_child(child)
      @children << child
    end

    def record_stop_time!(stop_time = Time.now)
      @stop_time = stop_time
    end

    # Fetch the current number of allocated objects. This will always increment - we fetch when initializing and when stopping the layer.
    def record_allocations!
      @allocations_stop = ScoutApm::Instruments::Allocations.count
    end

    def desc=(desc)
      @desc = desc
    end

    # This data is internal to ScoutApm, to add custom information, use the Context api.
    def annotate_layer(hsh)
      @annotations.merge!(hsh)
    end

    def subscopable!
      @subscopable = true
    end

    def subscopable?
      @subscopable
    end

    def traced!
      @traced = true
    end

    def traced?
      @traced
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

    # Set the name of the file that this action is coming from.
    # TraceSet uses this to more accurately filter backtraces
    def set_controller_file(file)
      @traces.set_controller_file(file)
    end

    def stack_index
      puts "STACK INDEX #{caller(3).size}"
      @stack_index ||= caller(3).size
    end

    def record_traces!
      ScoutApm::Instruments::Stacks.stop_sampling
      ScoutApm::Instruments::Stacks.profile_frames.each do |trace|
        @traces.add(trace)
      end
      if children.any?
        ScoutApm::Instruments::Stacks.update_indexes(children.first.stack_index, children.first.trace_index)
      else
        ScoutApm::Instruments::Stacks.update_indexes(0, 0)
      end
      ScoutApm::Instruments::Stacks.start_sampling
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
        Time.now - start_time
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

    ######################################
    # Allocation Calculations
    ######################################

    # These are almost identical to the timing metrics.

    def total_allocations
      if @allocations_stop > 0
        allocations = (@allocations_stop - @allocations_start)
      else
        allocations = (ScoutApm::Instruments::Allocations.count - @allocations_start)
      end
      allocations < 0 ? 0 : allocations
    end

    def total_exclusive_allocations
      total_allocations - child_allocations
    end

    def child_allocations
      children.
        map { |child| child.total_allocations }.
        inject(0) { |sum, obj| sum + obj }
    end
  end
end
