
require 'parser/current'
raise LoadError, "Parser::TreeRewriter was not defined" unless defined?(Parser::TreeRewriter)

module ScoutApm
  module AutoInstrument
    module ParserImplementation
      def self.rewrite(path, code = nil)
        code ||= File.read(path)

        ast = ::Parser::CurrentRuby.parse(code)

        buffer = ::Parser::Source::Buffer.new(path)
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

          # The stack of class nodes:
          @scope = []

          @cache = Cache.new
        end

        def instrument(source, file_name, line)
          # Don't log huge chunks of code... just the first line:
          if lines = source.lines and lines.count > 1
            source = lines.first.chomp + "..."
          end

          method_name = @method.last.children[0]
          bt = ["#{file_name}:#{line}:in `#{method_name}'"]

          return [
            "::ScoutApm::AutoInstrument("+ source.dump + ",#{bt}){",
            "}"
          ]
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
          column = node.location.column || 'column?' # not used
          method_name = node.children[0].children[1] || '*unknown*' # not used
          file_name = @source_rewriter.source_buffer.name

          wrap(node.location.expression, *instrument(node.location.expression.source, file_name, line))
        end

        def on_mlhs(node)
          # Ignore / don't instrument multiple assignment (LHS).
          return
        end

        def on_op_asgn(node)
          process(node.children[2])
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

          if @cache.local_assignments?(node)
            return super
          end

          # This ignores both initial block method invocation `*x*{}`, and subsequent nested invocations `x{*y*}`:
          return if parent_type?(:block)

          # Extract useful metadata for instrumentation:
          line = node.location.line || 'line?'
          column = node.location.column || 'column?' # not used
          method_name = node.children[1] || '*unknown*' # not used
          file_name = @source_rewriter.source_buffer.name

          # Wrap the expression with instrumentation:
          wrap(node.location.expression, *instrument(node.location.expression.source, file_name, line))
        end

        def on_hash(node)
          node.children.each do |pair|
            # Skip `pair` if we're sure it's not using the hash shorthand syntax
            next if pair.type != :pair
            key_node, value_node = pair.children
            next unless key_node.type == :sym && value_node.type == :send
            key = key_node.children[0]
            next unless value_node.children.size == 2 && value_node.children[0].nil? && key == value_node.children[1]

            # Extract useful metadata for instrumentation:
            line = pair.location.line || 'line?'
            # column = pair.location.column || 'column?' # not used
            # method_name = key || '*unknown*' # not used
            file_name = @source_rewriter.source_buffer.name

            instrument_before, instrument_after = instrument(pair.location.expression.source, file_name, line)
            replace(pair.loc.expression, "#{key}: #{instrument_before}#{key}#{instrument_after}")
          end
          super
        end

        # Invoked for every AST node as it is processed top to bottom.
        def process(node)
          # We are nesting inside this node:
          @nesting.push(node)

          if node and node.type == :def
            # If the node is a method, push it on the method stack as well:
            @method.push(node)
            super
            @method.pop
          elsif node and node.type == :class
            @scope.push(node.children[0])
            super
            @scope.pop
          else
            super
          end

          @nesting.pop
        end
      end
    end

    class Cache
      def initialize
        @local_assignments = {}
      end

      def local_assignments?(node)
        unless @local_assignments.key?(node)
          if node.type == :lvasgn
            @local_assignments[node] = true
          elsif node.children.find{|child| child.is_a?(Parser::AST::Node) && self.local_assignments?(child)}
            @local_assignments[node] = true
          else
            @local_assignments[node] = false
          end
        end

        return @local_assignments[node]
      end
    end
  end
end
