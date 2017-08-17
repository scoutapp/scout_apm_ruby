module ScoutApm
  module LayerConverters
    class Histograms < ConverterBase
      # Updates immediate and long-term histograms for both job and web requests
      def record!
        if request.unique_name != :unknown
          ScoutApm::Agent.instance.request_histograms.add(request.unique_name, root_layer.total_call_time)
          ScoutApm::Agent.instance.request_histograms_by_time[@store.current_timestamp].
            add(request.unique_name, root_layer.total_call_time)
        end
      end
    end
  end
end
