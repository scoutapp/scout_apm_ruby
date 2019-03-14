
module ScoutApm
  module AutoInstrument
    module Rails
      # A general pattern to match Rails controller files:
      CONTROLLER_FILE = /\/app\/controllers\/.*_controller.rb$/.freeze

      # Some gems (Devise) provide controllers that match CONTROLLER_FILE pattern.
      # Try a simple match to see if it's a Gemfile
      GEM_FILE = /\/gems?\//.freeze

      # Whether the given path is likely to be a Rails controller and not provided by a Gem.
      def self.controller_path? path
        CONTROLLER_FILE.match(path) && !GEM_FILE.match(path)
      end

      def self.rewrite(path, code = nil)
        code ||= File.read(path)

        ast = Parser::CurrentRuby.parse(code)

        # pp ast

        buffer = Parser::Source::Buffer.new(path)
        buffer.source = code

        rewriter = Rewriter.new

        # Rewrite the AST, returns a String with the new form.
        rewriter.rewrite(buffer, ast)
      end

      class Rewriter < ::Parser::TreeRewriter
        def initialize
          super

          # Keeps track of the parent - child relationship between nodes:
          @nesting = []

          # The stack of method nodes (type :def):
          @method = []
        end

        def instrument(source, line, column)
          # Don't log huge chunks of code... just the first line:
          if lines = source.lines and lines.count > 1
            source = lines.first.chomp + "..."
          end

          method_name = @method.last.children[0]

          ["::ScoutApm::AutoInstrument(\"\#{self.class}\\\##{method_name}:#{line}\", #{source.dump}){", "}"]
        end

        # Look up 1 or more nodes to check if the parent exists and matches the given type.
        # @param type [Symbol] the symbol type to match.
        # @param up [Integer] how far up to look.
        def parent_type?(type, up = 1)
          parent = @nesting[@nesting.size - up - 1] and parent.type == type
        end

        def on_block(node)
          # If we are not in a method, don't do any instrumentation:
          return if @method.empty?

          line = node.location.line || 'line?'
          column = node.location.column || 'column?'
          method_name = node.children[0].children[1] || '*unknown*'

          wrap(node.location.expression, *instrument(node.location.expression.source, line, column))
        end

        def on_or_asgn(node)
          process(node.children[1])
        end

        def on_and_asgn(node)
          process(node.children[1])
        end

        # Handle the method call AST node. If this method doesn't call `super`, no futher rewriting is applied to children.
        def on_send(node)
          # We aren't interested in top level function calls:
          return if @method.empty?

          # This ignores both initial block method invocation `*x*{}`, and subsequent nested invocations `x{*y*}`:
          return if parent_type?(:block)

          # Extract useful metadata for instrumentation:
          line = node.location.line || 'line?'
          column = node.location.column || 'column?'
          method_name = node.children[1] || '*unknown*'

          # Wrap the expression with instrumentation:
          wrap(node.location.expression, *instrument(node.location.expression.source, line, column))
        end

        # def on_class(node)
        #   class_name = node.children[1]
        # 
        #   Kernel.const_get(class_name).ancestors.include? ActionController::Controller
        # 
        #   if class_name =~ /.../
        #     super # continue processing
        #   end
        # end

        # Invoked for every AST node as it is processed top to bottom.
        def process(node)
          # We are nesting inside this node:
          @nesting.push(node)

          if node and node.type == :def
            # If the node is a method, push it on the method stack as well:
            @method.push(node)
            super
            @method.pop
          else
            super
          end

          @nesting.pop
        end
      end
    end
  end
end

# Force any lazy loading to occur here, before we patch iseq_load. Otherwise you might end up in an infinite loop when rewriting code.
ScoutApm::AutoInstrument::Rails.rewrite('(preload)', '')
