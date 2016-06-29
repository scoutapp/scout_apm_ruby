module ScoutApm
  class Stacks
    def self.collect(frames)
      req = RequestManager.lookup
      current_layer = req.current_layer
      if current_layer
        current_layer.store_frames!(frames)
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
