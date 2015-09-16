module ScoutApm
  class StackprofTreeCollapser
    attr_reader :raw_stackprof
    attr_reader :nodes # the current set of nodes under consideration

    def initialize(raw_stackprof)
      @raw_stackprof = raw_stackprof
    end

    def call
      build_tree
      connect_children
      collapse_tree
      generate_output
    end

    private

    def build_tree
      @nodes = raw_stackprof[:frames].map do |(frame_id, frame_data)|
        TreeNode.new(frame_id,                     # frame_id
                     frame_data[:name],            # name
                     frame_data[:file],            # file
                     frame_data[:line],            # line
                     frame_data[:samples],         # samples
                     (frame_data[:edges] || {}),   # children_edges [ { id => weight } ]
                     nil,                          # children [ treenode, ... ]
                     []                            # parents [ [treenode, int (weight) ], [...] ]
                    )
      end

    end

    def connect_children
      nodes.each do |node|
        children = nodes.find_all { |n| node.children_edges.keys.include? n.frame_id }

        node.children_edges.each do |(frame_id, weight)|
          child = children.detect{ |c| c.frame_id == frame_id }
          child.parents << [node, weight]
        end

        node.children = children
      end
    end

    def collapse_tree
      while true
        number_changed = collapse_tree_one_level
        break if number_changed == 0
      end
    end

    # For each leaf node, sees if it is internal to the monitored app. If not,
    # collapse that node to its parents, weighted by the edge counts
    # If that node was internal to the monitored app, leave it.
    # Returns 0 if nothing changed, a positive integer if things did change,
    # indicating how many leaves were collapsed
    def collapse_tree_one_level
      number_changed = 0

      leaves(nodes).each do |leaf_node|
        next if leaf_node.app?
        number_changed += 1
        leaf_node.collapse_to_parent!
        nodes.delete(leaf_node)
      end

      number_changed
    end

    # Returns the final result, an array of hashes
    def generate_output
      leaves(nodes).map{|x| { name: x.name, samples: x.samples, file: x.file, line: x.line } }
    end

    # A leaf node has no children.
    def leaves(node_list)
      node_list.find_all { |n| n.children.empty? }
    end

    ###########################################
    # TreeNode class represents a single node.
    ###########################################
    TreeNode = Struct.new(:frame_id, :name, :file, :line, :samples,
                          :children_edges, :children, :parents) do
      def app?
        file =~ /^#{ScoutApm::Environment.instance.root}/
      end

      # Allocate this node's samples to its parents, in relation to the rate at
      # which each parent called this method.  Then clear the child from each of the parents
      def collapse_to_parent!
        total_weight = parents.map{ |p| p[1] }.inject(0){ |sum, weight| sum + weight }
        parents.each do |(p_node, weight)|
          relative_weight = weight.to_f / total_weight.to_f
          p_node.samples += (samples * relative_weight)
        end

        parents.each {|(p_node, _)| p_node.delete_child!(self) }
      end

      def delete_child!(node)
        children.delete(self)
      end

      # Force object_id to be the equality mechanism, rather than struct's
      # default which delegates to == on each value.  That is wrong because
      # we want to be able to dup a node in the tree construction process and
      # not have those compare equal to each other.
      def ==(other)
        object_id == other.object_id
      end
    end
  end
end
