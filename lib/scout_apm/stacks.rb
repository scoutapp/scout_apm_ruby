module ScoutApm
  class StackTrace
    attr_reader :data
    attr_reader :num

    def initialize(num)
      puts "Initialized, expecting #{num}"
      @num = num
      @data = []
    end

    def add(file, line, label, klass)
      @data << [file, line, label, klass]
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
