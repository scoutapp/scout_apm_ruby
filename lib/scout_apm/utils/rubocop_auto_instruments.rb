module RuboCop
  module Cop
    module ActionController
      class AddScoutInstruments < RuboCop::Cop::Cop
        MSG = ''

        def on_send(send_node)
          if (!scout_send?(send_node) || !scout_send?(send_node.parent)) && send_node.block_node.nil?
            add_offense(send_node, location: :expression) unless scout_send?(send_node) || scout_send?(send_node.parent)
          end
        end

        def autocorrect(node)
          ->(corrector) do
            line = node.loc.try(:line) || 'line?'
            col = node.loc.try(:column) || 'col?'
            method_name = node.method_name || 'Unknown'
            corrector.replace(node.source_range, "ScoutApm::Instruments::AutoInstruments.dynamic_layer('#{method_name}:l#{line}:c#{col}'){#{node.source}}")
          end
        end

        def_node_matcher :scout_send?, '(send _ :scout (...) )'

      end
    end
  end
end