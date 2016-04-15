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

      # Account for Darwin returning maxrss in bytes and Linux in KB. Used by the slow converters. Doesn't feel like this should go here though...more of a utility.
      def rss_to_mb(rss)
        rss.to_f/1024/(ScoutApm::Agent.instance.environment.os == 'darwin' ? 1024 : 1)
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
