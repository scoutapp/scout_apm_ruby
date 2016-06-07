module ScoutApm
  class TraceSet
    attr_reader :traces
    attr_reader :size
    alias_method :length, :size

    # The aggregated metrics around a bunch of distinct traces.
    attr_reader :aggregated

    def initialize
      @traces = []
      @delayed_traces = []
      @size = 0
      @aggregated = Hash.new{|h,k| h[k] = [] }
    end

    def to_a
      @traces.map(&:to_a)
    end

    def add(trace)
      @traces << trace
    end

    # Take any delayed traces and absorb them
    def aggregate!
      traces.each do |trace|
        absorb(trace)
      end
    end

    # Take an individual trace, and add it to the summary
    def absorb(trace)
      if trace.app_trace?
        app_line = trace.first
        @aggregated["#{app_line.klass}##{app_line.label}"] += [trace.app_code]
      elsif gem_line = trace.gem_before_app_code
        gem_line = trace.gem_before_app_code
        @aggregated[gem_line.gem_name] += [trace.app_code]
      else
        # TODO: No app code I suppose?
      end
    end

    def inspect
      to_s
    end

    def to_s
      aggregate!

      "Out of #{traces.length} traces: \n" + (@aggregated.map {|gem_name, lines|
        "#{gem_name} called from:\n\t#{lines.map(&:to_s).join("\n\t")}"
      }.join("\n"))
    end
  end

  class StackLine
    attr_reader :file
    attr_reader :line
    attr_reader :label
    attr_reader :klass
    attr_reader :app

    def initialize(file, line, label, klass)
      @file = file
      @line = line
      @label = label
      @klass = klass
      @app = (app? rescue false)
    end

    def to_a
      [file, line, label, klass, app]
    end

    def to_s
      gem_clause = gem_name if gem_name
      app_clause = "APP" if app?
      clauses = [gem_clause, app_clause].join("")
      clauses = "ALERT! #{clauses}" if gem_clause.present? && app_clause.present?

      "#{clauses} - #{klass}##{label}\t#{file}:#{line}"
    end

    def inspect
      to_s
    end

    # This may match several times. For instance, this path has gems/RUBY/gems/GEM
    # /Users/cschneid/.rvm/gems/ruby-2.2.2/gems/unicorn-5.0.1/lib/unicorn/http_server.rb
    #
    # The last one is the one we want.
    # returns nil if no match
    def gem_name
      @gem_name ||= begin
                      r = %r{gems/(.*?)/}
                      results = file.scan(r)
                      results[-1][0] # Scan will return a nested array, so extract out that nesting
                    rescue
                      nil
                    end
    end

    def app?(app_root=ScoutApm::Environment.instance.root)
      @app ||= begin
                 m = file.match(%r{#{app_root}/(.*)})
                 m[1] if m
               end
    end
  end

  class StackTrace
    include Enumerable

    attr_reader :data
    attr_reader :num

    def initialize(num)
      @num = num
      @data = []
    end

    def each
      @data.each { |d| yield d }
    end

    def add(file, line, label, klass)
      return if file.nil?

      @data << StackLine.new(file, line, label, klass)
    end

    def inspect
      "#{num} entries: \n #{@data.map(&:inspect).join("\n")}"
    end

    def gem_before_app_code
      gem_line = nil
      hit_app_code = false

      data.each do |d|
        if d.app?
          hit_app_code = true
          break
        end

        if d.gem_name
          gem_line = d
        end
      end

      return gem_line if hit_app_code
      nil
    end

    # returns StackLine representing first app code hit
    def app_code
      data.detect { |d| d.app? }
    end

    # Return true if the top of the stack is inside the app
    def app_trace?
      data.first.app?
    end
  end

  class Stacks
    def self.collect(trace)
      req = RequestManager.lookup
      current_layer = req.current_layer
      if current_layer
        current_layer.store_trace!(trace)
      end
    rescue => e
      puts "\n\n\n*****************************"
      puts "Error: #{e}"
      puts e.backtrace
      puts "*****************************\n\n\n"
    end
  end
end
