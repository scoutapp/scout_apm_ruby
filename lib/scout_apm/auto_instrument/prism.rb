
require 'prism'

module ScoutApm
  module AutoInstrument
    module PrismImplementation
      def self.rewrite(path, code = nil)
        code ||= File.read(path)

        result = Prism.parse(code)
        rewriter = Rewriter.new(path, code)
        rewriter.rewrite(result.value)
      end

      class Rewriter
        def initialize(path, code)
          @path = path
          # Set encoding to ASCII-8bit as Prism uses byte offsets
          @code = code.b
          @replacements = []
          @instrumented_nodes = Set.new

          # Keeps track of the parent - child relationship between nodes:
          @nesting = []

          # The stack of method nodes:
          @method = []

          # The stack of class nodes:
          @scope = []

          @cache = Cache.new
        end

        def rewrite(node)
          process(node)
          apply_replacements
        end

        def apply_replacements
          # Sort replacements by start position in reverse order
          # This ensures we apply replacements from end to start, avoiding offset issues
          # when we modify the string
          sorted_replacements = @replacements.sort_by { |r| -r[:start] }

          result = @code.dup
          sorted_replacements.each do |replacement|
            result[replacement[:start]...replacement[:end]] = replacement[:new_text].b
          end
          # ::RubyVM::InstructionSequence.compile will infer the encoding when compiling
          # and will compile with ASCII-8bit correctly.
          result
        end

        def add_replacement(start_offset, end_offset, new_text)
          @replacements << {start: start_offset, end: end_offset, new_text: new_text}
        end

        def instrument(source, file_name, line)
          # Don't log huge chunks of code... just the first line:
          if lines = source.lines and lines.count > 1
            source = lines.first.chomp + "..."
          end

          method_name = @method.last.name
          bt = ["#{file_name}:#{line}:in `#{method_name}'"]

          return [
            "::ScoutApm::AutoInstrument("+ source.dump + ",#{bt}){",
            "}"
          ]
        end

        # Look up 1 or more nodes to check if the parent exists and matches the given type.
        # @param type [Class] the node class to match.
        # @param up [Integer] how far up to look.
        def parent_type?(type, up = 1)
          parent = @nesting[@nesting.size - up - 1] and parent.is_a?(type)
        end

        def wrap_node(node)
          # Skip if this node or any parent has already been instrumented
          return if @instrumented_nodes.include?(node)

          # Skip if any ancestor node has been instrumented (to avoid overlapping replacements)
          @nesting.each do |ancestor|
            return if @instrumented_nodes.include?(ancestor)
          end

          # Skip if any descendant node has already been instrumented (to avoid overlapping replacements)
          # This prevents a parent node from being wrapped when a child node has already been modified
          return if has_instrumented_descendant?(node)

          start_offset = node.location.start_offset
          end_offset = node.location.end_offset
          line = node.location.start_line
          source = @code[start_offset...end_offset]

          instrument_before, instrument_after = instrument(source, @path, line)
          new_text = "#{instrument_before}#{source}#{instrument_after}"
          add_replacement(start_offset, end_offset, new_text)
          @instrumented_nodes.add(node)
        end

        def has_instrumented_descendant?(node)
          node.compact_child_nodes.any? do |child|
            @instrumented_nodes.include?(child) || has_instrumented_descendant?(child)
          end
        end

        def visit_block_node(node)
          # If we are not in a method, don't do any instrumentation:
          return process_children(node) if @method.empty?

          # If this block is attached to a CallNode, don't wrap it separately
          # The CallNode will wrap the entire call including the block
          return process_children(node) if parent_type?(Prism::CallNode)

          # If this block is attached to a SuperNode or ForwardingSuperNode, don't wrap it separately
          # The super node will wrap the entire call including the block
          return process_children(node) if parent_type?(Prism::SuperNode) || parent_type?(Prism::ForwardingSuperNode)

          wrap_node(node)
        end

        def visit_multi_target_node(node)
          # Ignore / don't instrument multiple assignment (LHS).
          return
        end

        def visit_call_node(node)
          # We aren't interested in top level function calls:
          return process_children(node) if @method.empty?

          if @cache.local_assignments?(node)
            return process_children(node)
          end

          # This ignores both initial block method invocation and subsequent nested invocations:
          return process_children(node) if parent_type?(Prism::BlockNode)

          wrap_node(node)

          # Process children to handle nested calls, but blocks attached to this call
          # won't be wrapped separately (handled by visit_block_node check)
          process_children(node)
        end

        def visit_super_node(node)
          # We aren't interested in top level super calls:
          return process_children(node) if @method.empty?

          # This ignores super calls inside blocks:
          return process_children(node) if parent_type?(Prism::BlockNode)

          # Only wrap super calls that have a block attached
          # Bare super calls (with or without arguments) are just delegation and shouldn't be instrumented
          if node.block
            wrap_node(node)
          end

          # Process children to handle nested calls, but blocks attached to this super
          # won't be wrapped separately (handled by visit_block_node check)
          process_children(node)
        end

        def visit_forwarding_super_node(node)
          # We aren't interested in top level super calls:
          return process_children(node) if @method.empty?

          # This ignores super calls inside blocks:
          return process_children(node) if parent_type?(Prism::BlockNode)

          # Only wrap super calls that have a block attached
          # Bare super calls are just delegation and shouldn't be instrumented
          if node.block
            wrap_node(node)
          end

          # Process children to handle nested calls, but blocks attached to this super
          # won't be wrapped separately (handled by visit_block_node check)
          process_children(node)
        end

        # This is meant to mirror that of the parser implementation.
        # See test/unit/auto_instrument/hash_shorthand_controller-instrumented.rb
        # Non-nil receiver is handled in visit_call_node.
        def visit_hash_node(node)
          # If this hash is a descendant of a CallNode (at any level), don't instrument individual elements
          # The parent CallNode will wrap the entire expression
          # This allows hashes in local variable assignments to be instrumented,
          # but hashes in method calls to be wrapped as a unit
          in_call_node = @nesting.any? { |n| n.is_a?(Prism::CallNode) }

          node.elements.each do |element|
            if element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
              value_node = element.value

              # Only instrument hash element values if we're not in a CallNode
              # Handles shorthand syntax like `shorthand:` → line 6
              if !in_call_node && value_node.is_a?(Prism::ImplicitNode)
                key = element.key.unescaped
                inner_call = value_node.value

                line = element.location.start_line
                source = @code[element.location.start_offset...element.location.end_offset]
                file_name = @path
                method_name = @method.last.name
                bt = ["#{file_name}:#{line}:in `#{method_name}'"]

                instrument_before = "::ScoutApm::AutoInstrument(#{source.dump},#{bt}){"
                instrument_after = "}"
                new_text = "#{key}: #{instrument_before}#{key}#{instrument_after}"
                add_replacement(element.location.start_offset, element.location.end_offset, new_text)

                @instrumented_nodes.add(value_node)
                @instrumented_nodes.add(inner_call)
                next
              elsif !in_call_node && value_node.is_a?(Prism::CallNode) && value_node.receiver.nil?
                line = element.location.start_line
                key = element.key.unescaped
                value_name = value_node.name.to_s
                pair_source = @code[element.location.start_offset...element.location.end_offset]
                value_source = @code[value_node.location.start_offset...value_node.location.end_offset]
                key_source = @code[element.key.location.start_offset...element.key.location.end_offset]
                file_name = @path
                method_name = @method.last.name
                bt = ["#{file_name}:#{line}:in `#{method_name}'"]

                has_arguments = value_node.arguments && !value_node.arguments.arguments.empty?

                # Handles hash_rocket w/ same key/value name and no arguments.
                # See test for more info on backward compatibility on this one.
                # e.g. `hash_rocket: hash_rocket` → line 9
                if key == value_name && !has_arguments && key_source.start_with?(':')
                  source_for_dump = pair_source
                  instrument_before = "::ScoutApm::AutoInstrument(#{source_for_dump.dump},#{bt}){"
                  instrument_after = "}"
                  instrumented_value = "#{instrument_before}#{value_source}#{instrument_after}"
                  new_text = "#{key}: #{instrumented_value}"
                  add_replacement(element.location.start_offset, element.location.end_offset, new_text)

                # If key == value_name and no arguments → direct shorthand pair
                # e.g. `longhand: longhand` → line 7
                elsif key == value_name && !has_arguments && !key_source.start_with?(':')
                  source_for_dump = pair_source
                  instrument_before = "::ScoutApm::AutoInstrument(#{source_for_dump.dump},#{bt}){"
                  instrument_after = "}"
                  instrumented_value = "#{instrument_before}#{value_source}#{instrument_after}"
                  add_replacement(value_node.location.start_offset, value_node.location.end_offset, instrumented_value)

                # If key != value_name → “different key/value name” case
                # e.g. `longhand_different_key: longhand` → line 8  
                # or `:hash_rocket_different_key => hash_rocket` → line 10
                elsif key != value_name && !has_arguments
                  source_for_dump = value_source
                  instrument_before = "::ScoutApm::AutoInstrument(#{source_for_dump.dump},#{bt}){"
                  instrument_after = "}"
                  instrumented_value = "#{instrument_before}#{value_source}#{instrument_after}"
                  add_replacement(value_node.location.start_offset, value_node.location.end_offset, instrumented_value)

                # If value_node has arguments → method call with params
                # e.g. `nested_call(params["timestamp"])` → line 15
                elsif has_arguments
                  source_for_dump = value_source
                  instrument_before = "::ScoutApm::AutoInstrument(#{source_for_dump.dump},#{bt}){"
                  instrument_after = "}"
                  instrumented_value = "#{instrument_before}#{value_source}#{instrument_after}"
                  add_replacement(value_node.location.start_offset, value_node.location.end_offset, instrumented_value)
                end

                @instrumented_nodes.add(value_node)
                next
              end
            end

            element.compact_child_nodes.each do |child|
              process(child)
            end
          end
        end

        def process(node)
          return unless node

          # We are nesting inside this node:
          @nesting.push(node)

          case node
          when Prism::DefNode
            # If the node is a method, push it on the method stack as well:
            @method.push(node)
            process_children(node)
            @method.pop
          when Prism::ClassNode
            # If the node is a method, push it on the scope stack as well:
            @scope.push(node.name)
            process_children(node)
            @scope.pop
          when Prism::BlockNode
            visit_block_node(node)
          when Prism::MultiTargetNode
            visit_multi_target_node(node)
          when Prism::CallNode
            visit_call_node(node)
          when Prism::SuperNode
            visit_super_node(node)
          when Prism::ForwardingSuperNode
            visit_forwarding_super_node(node)
          when Prism::HashNode
            visit_hash_node(node)
          when Prism::CallOperatorWriteNode, Prism::CallOrWriteNode, Prism::CallAndWriteNode
            # For op assignment nodes, only process the value
            process(node.value)
          else
            process_children(node)
          end

          @nesting.pop
        end

        def process_children(node)
          node.compact_child_nodes.each do |child|
            process(child)
          end
        end
      end
    end

    class Cache
      def initialize
        @local_assignments = {}
      end

      def local_assignments?(node)
        return false unless node
        return false unless node.respond_to?(:compact_child_nodes)

        unless @local_assignments.key?(node)
          if node.is_a?(Prism::LocalVariableWriteNode)
            @local_assignments[node] = true
          elsif node.compact_child_nodes.find{|child|
            # Don't check blocks - assignments inside blocks shouldn't affect the parent call
            next if child.is_a?(Prism::BlockNode)
            self.local_assignments?(child)
          }
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
