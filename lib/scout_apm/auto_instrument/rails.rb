
# In order for this to work, you must add `gem 'parser'` to your Gemfile.
require 'parser/current'

module ScoutApm
  module AutoInstrument
    module Rails
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

          @nesting = []
          @method = []
        end

        def parent_type?(type, up = 1)
          parent = @nesting[@nesting.size - up - 1] and parent.type == type
        end

        # def on_block(node)
        #   line = node.location.line || 'line?'
        #   column = node.location.column || 'column?'
        #   method_name = node.children[0].children[1] || '*unknown*'
        #
        #   wrap(node.location.expression, "::ScoutApm::Instruments::AutoInstruments.dynamic_layer('#{method_name}:l#{line}:c#{column}'){", "}")
        # end

        def on_send(node)
          return if parent_type?(:block) or @method.empty?

          line = node.location.line || 'line?'
          column = node.location.column || 'column?'
          method_name = node.children[1] || '*unknown*'

          wrap(node.location.expression, "::ScoutApm::Instruments::AutoInstruments.dynamic_layer('#{method_name}:l#{line}:c#{column}'){", "}")
        end

        def process(node)
          @nesting.push(node)

          if node and node.type == :def
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
