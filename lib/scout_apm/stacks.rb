module ScoutApm
  class TraceSet
    attr_reader :traces

    def initialize
      @traces = []
      @aggregated = Hash.new{|h,k| h[k] = [] }
    end

    def <<(trace)
      @traces << trace

      if trace.app_trace?
        @aggregated["APP"] += [trace.app_code]
      else
        gem_line = trace.gem_before_app_code
        @aggregated[gem_line.gem] += [trace.app_code]
      end
    end

    def inspect
      to_s
    end

    def to_s
      @aggregated.map {|gem, lines|
        "#{gem} called from:\n\t#{lines.map(&:to_s).join("\n\t")}"
      }.join("\n")
    end
  end

  class StackLine
    attr_reader :file
    attr_reader :line
    attr_reader :label
    attr_reader :klass

    def initialize(file, line, label, klass)
      @file = file
      @line = line
      @label = label
      @klass = klass
    end

    def to_s
      gem_clause = gem if gem
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
    def gem
      @gem ||= begin
                 r = %r{gems/(.*?)/}
                 results = file.scan(r)
                 results[-1]
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
    attr_reader :data
    attr_reader :num

    def initialize(num)
      @num = num
      @data = []
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

        if d.gem
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
      puts "Error: #{e}"
    end
  end
end
