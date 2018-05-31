module ScoutApm
  module Instruments
    class AutoInstruments
      def self.dynamic_layer(name)
        req = ScoutApm::RequestManager.lookup

        begin
          layer = ScoutApm::Layer.new('AutoInstrument', name)
          req.start_layer(layer)
          started_layer = true
          puts "================ STARTED AUTO INSTRUMENT LAYER #{name} ============="
          puts layer.to_s
          res = yield
          puts "================ FINISHED AUTO INSTRUMENT LAYER #{name} ============="
        rescue
          req.error!
          raise
        ensure
          req.stop_layer if started_layer
        end
        res
      end
    end
  end
end