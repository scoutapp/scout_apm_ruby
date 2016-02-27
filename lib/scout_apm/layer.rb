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

    attr_reader :stack_profile

    def initialize(type, name, start_time = Time.now)
      @type = type
      @name = name
      @start_time = start_time
      @children = [] # In order of calls
      @desc = nil
      @stack_profile = nil
    end

    def add_child(child)
      @children << child
    end

    def record_stop_time!(stop_time = Time.now)
      @stop_time = stop_time
    end

    # Takes an array of GC Generation IDs to exclude from this layer. Want to exclude generations that started and ended earlier.
    def record_gc_data(exclude_gc_generations)
      # just exclude generations that started & ended, right?
      events = ScoutApm::StackProfile.gc_event_datas_for(start_time, stop_time).reject { |e| exclude_gc_generations.include?(e[:start_gc_count]) }
      @stack_profile = ScoutApm::StackProfile.new(events)
      if @stack_profile.rss_increased?
        req = ScoutApm::RequestManager.lookup
        dbg = {}
        ScoutApm::Agent.instance.logger.info dbg.merge!(layer: legacy_metric_name, pid: Process.pid, uri: req.annotations[:uri], rss: rss_to_s(@stack_profile.gc_events.sort!{|a,b| a.gc_data[:gc_start_count] <=> b.gc_data[:gc_start_count]}.last.gc_data[:end_max_rss]), rss_diff: rss_to_s(@stack_profile.rss_size_diff), gc_events: @stack_profile.gc_events.map { |e| "#{e.gc_data[:start_gc_count]} (#{rss_to_s(e.gc_data[:end_max_rss],units=false)}-#{rss_to_s(e.gc_data[:start_max_rss],units)}=#{rss_to_s(e.rss_size_diff,units)})"})
      end

      events.map { |e| e[:start_gc_count]}
    end

    ## temporary hack - display memory as string in MB. needs to account for osx showingin bytes and linux in KB.
    def rss_to_s(rss,units=true)
      (rss.to_f/1024/(ScoutApm::Agent.instance.environment.os == :macosx ? 1024 : 1)).round(2).to_s + (units ? " MB" : '')
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

    def store_backtrace(bt)
      return unless bt.is_a? Array
      return unless bt.length > 0
      @backtrace = bt
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
