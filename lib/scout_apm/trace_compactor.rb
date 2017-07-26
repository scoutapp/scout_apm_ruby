# Takes in a ton of traces. Structure is a several nested arrays:
# [                             # Traces
#    [                          # Trace
#      [file,line,method,klass] # TraceLine (raw)
#    ]
# ]
#
# Cleans them
# Merges them by gem/app
#
module ScoutApm
class TraceSet
  # A TraceCube object which is a glorified hash of { Trace -> Count }. Used to
  # collect up the count of each unique trace we've seen
  attr_reader :cube
  attr_accessor :raw_trace

  def initialize
    @raw_trace = []
    @cube = TraceCube.new
  end

  # We need to know what the "Start" of this trace is.  An untrimmed trace generally is:
  #
  # Gem
  # Gem
  # App
  # App
  # App <---- set root_class of this.
  # Rails
  # Rails
  def set_root_class(klass_name)
    @root_klass = klass_name.to_s
  end

  def to_a
    res = []
    create_cube!
    @cube.each do |(trace, count)|
      res << [trace.to_a, count]
    end

    res
  end

  def as_json
    res = []
    create_cube!
    @cube.each do |(trace, count)|
      res << [trace.as_json, count]
    end

    res
  end

  def create_cube!
    clean_trace = ScoutApm::CleanTrace.new(raw_trace, @root_klass)
    @cube << clean_trace
    @raw_trace = []
  end

  def total_count
    create_cube!
    cube.inject(0) do |sum, (_, count)|
      sum + count
    end
  end

  def inspect
    create_cube!
    cube.map do |(trace, count)|
      "\t#{count} -- #{trace.first.klass}##{trace.first.method}\n\t\t#{trace.to_a[1].try(:klass)}##{trace.to_a[1].try(:method)}"
    end.join("\n")
  end
end

# A trace is a list of individual lines, where one called another, forming a backtrace.
# Each line is made up of File, Line #, Klass, Method
#
# For the purpouses of this class:
#   "Top" of the trace means the currently-running method.
#   "Bottom" means the root of the call tree, from program start into rails and so on.
#
# This class trims off top and bottom to get a the meat of the trace
class CleanTrace
  include Enumerable

  attr_reader :lines

  def initialize(raw_trace, root_klass=nil)
    @lines = Array(raw_trace).map {|file, lineno, method, klass| TraceLine.new(file, lineno, method, klass)}
    @root_klass = root_klass

    # A trace has interesting data in the middle of it, since normally it'll go
    # RailsCode -> App Code -> Gem Code.
    #
    # So we drop the code that leads up to your app, since a deep trace that
    # always says that you went through middleware and the rails router doesn't
    # help diagnose issues.
    drop_below_app

    # Then we drop most of the Gem Code, since you didn't write it, and in the
    # vast majority of the cases, the time spent there is because your app code
    # asked, not because of inherent issues with the gem. For instance, if you
    # fire off a slow query to a database gem, you probably want to be
    # optimizing the query, not trying to make the database gem faster.
    drop_above_app
  end

  # Iterate starting at END of array until a controller line is found. Pop off at that index - 1.
  def drop_below_app
    pops = 0
    index = lines.size - 1 # last index, not size.

    while index >= 0 && !lines[index].controller?(@root_klass)
      index -= 1
      pops += 1
    end

    lines.pop(pops)
  end

  # Find the closest mention of the application code from the currently-running method.
  # Then adjust by 1 if possible to capture the "first" line 
  def drop_above_app
    ai = @lines.find_index(&:app?)
    if ai
      ai -= 1 if ai > 0
      @lines = @lines[ai .. -1]
    else
      @lines = [] # No app line in backtrace, nothing to show?
    end
  end

  def each
    @lines.each { |line| yield line }
  end

  def empty?
    @lines.empty?
  end

  def as_json
    @lines.map { |line| line.as_json }
  end

  ###############################
  # Hash Key interface
  def hash
    @lines.hash
  end

  def eql?(other)
    @lines.eql?(other.lines)
  end
  ###############################
end

class TraceLine
  # An opaque C object, only call Stacks#frame_* methods on this.
  attr_reader :file
  attr_reader :lineno
  attr_reader :method
  attr_reader :klass

  def initialize(file, lineno, method, klass)
    @file = file
    @lineno = lineno
    @method = method
    @klass = klass.name
  end

  # Returns the name of the last gem in the line
  def gem_name
    @gem_name ||= begin
                    r = %r{\/gems/(.*?)/}.freeze
                    results = file.scan(r)
                    results[-1][0] # Scan will return a nested array, so extract out that nesting
                  rescue
                    nil
                  end
  end

  def stdlib_name
    @stdlib_name ||= begin
                    r = %r{#{Regexp.escape(RbConfig::TOPDIR)}/(.*?)}.freeze
                    results = file.scan(r)
                    results[-1][0] # Scan will return a nested array, so extract out that nesting
                  rescue
                    nil
                  end
  end

  def gem?
    !!gem_name
  end

  def stdlib?
    !!stdlib_name
  end

  def app?
    r = %r|^#{Regexp.escape(ScoutApm::Environment.instance.root.to_s)}/|.freeze
    result = !gem_name && !stdlib_name && file =~ r
    !!result # coerce to a bool
  end

  def trim_file(file_path)
    return if file_path.nil?
    if gem?
      r = %r{.*gems/.*?/}.freeze
      file_path.sub(r, "/")
    elsif stdlib?
      file_path.sub(RbConfig::TOPDIR, '')
    elsif app?
      file_path.sub(ScoutApm::Environment.instance.root.to_s, '')
    end
  end

  # If root_klass is provided, just see if this is exactly that class. If not,
  # fall back on "is this in the app"
  def controller?(root_klass)
    return false if klass.nil? # main function doesn't have a file associated

    if root_klass
      klass == root_klass
    else
      app?
    end
  end

  def formatted_to_s
    "#{stdlib_name} #{klass}##{method} -- #{file}:#{line}"
  end

  def as_json
    [ trim_file(file), lineno, klass, method, app?, gem_name, stdlib_name ]
  end

  ###############################
  # Hash Key interface

  def hash
    # Note that this does not include line number. It caused a few situations
    # where we had a bunch of time spent in one method, but across a few lines,
    # we decided that it made sense to group them together.
    file.hash ^ method.hash ^ klass.hash
  end

  def eql?(other)
    file == other.file &&
      method == other.method &&
      klass == other.klass
  end

  ###############################
end

# Collects clean traces and counts how many of each we have.
class TraceCube
  include Enumerable

  attr_reader :traces
  attr_reader :total_count

  def initialize
    @traces = Hash.new{ |h,k| h[k] = 0 }
    @total_count = 0
  end

  def <<(clean_trace)
    @total_count += 1
    @traces[clean_trace] += 1
  end

  # Yields two element array, the trace and the count of that trace
  # In descending order of count.
  def each
    @traces
      .to_a
      .each { |(trace, count)|
        next if trace.empty?
        yield [trace, count]
      }
  end
end
end

