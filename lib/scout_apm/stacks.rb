module ScoutApm
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
      raise
    end
  end
end
