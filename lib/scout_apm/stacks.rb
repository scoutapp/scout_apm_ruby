module ScoutApm
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
      r = %r{gems/(.*?)/}
      results = file.scan(r)
      results[-1]
    end

    def app?(app_root=ScoutApm::Environment.instance.root)
      m = file.match(%r{#{app_root}/(.*)})
      if m
        return m[1]
      end
    end
  end

  class StackTrace
    attr_reader :data
    attr_reader :num

    def initialize(num)
      puts "Initialized, expecting #{num}"
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
