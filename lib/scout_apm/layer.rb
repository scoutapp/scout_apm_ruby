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

    # A hash of annotations about this layer
    #   Examples:
    #     :sql => "SELECT * FROM users WHERE id = ?"
    #     :stacktrace => "...."
    #     :url => "http://..."
    attr_reader :annotations

    def initialize(type, name, start_time = Time.now)
      @type = type
      @name = name
      @start_time = start_time
      @children = [] # In order of calls
      @annotations = {}
    end

    def add_child(child)
      @children << child
    end

    def record_stop_time(stop_time = Time.now)
      @stop_time = stop_time
    end

    def annotate_layer(new_annotations={})
      @annotations.merge!(new_annotations)
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
