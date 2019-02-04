
module ScoutApm
  def self.AutoInstrument(name)
    request = ScoutApm::RequestManager.lookup

    begin
      layer = ScoutApm::Layer.new('AutoInstrument', name)
      request.start_layer(layer)
      started_layer = true

      result = yield
    rescue
      request.error!
      raise
    ensure
      request.stop_layer if started_layer
    end

    return result
  end
end
