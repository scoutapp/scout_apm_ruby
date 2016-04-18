module ScoutApm
  module LayerConverters
    class ConverterBase
      attr_reader :walker
      attr_reader :request
      attr_reader :root_layer

      def initialize(request)
        @request = request
        @root_layer = request.root_layer
        @walker = DepthFirstWalker.new(root_layer)
      end

      # Scope is determined by the first Controller we hit.  Most of the time
      # there will only be 1 anyway.  But if you have a controller that calls
      # another controller method, we may pick that up:
      #     def update
      #       show
      #       render :update
      #     end
      def scope_layer
        @scope_layer ||= walker.walk do |layer|
          if layer.type == "Controller"
            break layer
          end
        end
      end
    end
  end
end
