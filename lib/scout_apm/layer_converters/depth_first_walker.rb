module ScoutApm
  module LayerConverters
    class DepthFirstWalker
      attr_reader :root_layer

      def initialize(root_layer)
        @root_layer = root_layer
      end

      def before(&block)
        @before_block = block
      end

      def after(&block)
        @after_block = block
      end

      def walk(layer=root_layer, &block)
        # Need to run this for the root layer the first time through.
        if layer == root_layer
          @before_block.call(layer) if @before_block
          yield layer
          @after_block.call(layer) if @after_block
        end

        layer.children.each do |child|
          @before_block.call(child) if @before_block
          yield child
          walk(child, &block)
          @after_block.call(child) if @after_block
        end
        nil
      end
    end
  end
end
