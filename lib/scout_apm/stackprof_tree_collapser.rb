# require 'json'; p = JSON::parse(File.read("/Users/cschneid/example_stackprof.out")); p=p.with_indifferent_access; ScoutApm::StackprofTreeCollapser.new(p).call
# require 'json'; p = JSON::parse(File.read("/Users/cschneid/profile_appscontroller.json")); p=p.with_indifferent_access; ScoutApm::StackprofTreeCollapser.new(p).call
# require 'json'; p = JSON::parse(File.read("/Users/cschneid/profile_elasticsearch.json")); p=p.with_indifferent_access; ScoutApm::StackprofTreeCollapser.new(p).call


module ScoutApm
  class StackprofTreeCollapser
    attr_reader :raw_stackprof
    attr_reader :nodes # the current set of nodes under consideration

    def initialize(raw_stackprof)
      @raw_stackprof = raw_stackprof
      ScoutApm::Agent.instance.logger.info("StackProf - Samples: #{raw_stackprof[:samples]}, GC: #{raw_stackprof[:gc_samples]}, missed: #{raw_stackprof[:missed_samples]}, Interval: #{raw_stackprof[:interval]}")
    end

    def call
      build_tree
      connect_children
      $max_node = nodes.max_by{|n| n.samples }
      binding.pry
      # calculate_results
      # collapse_tree
      # generate_output
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
                     [],                           # children [ treenode, ... ]
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

    # @results will be [{name, samples, file, line}]
    def calculate_results
      @results = in_app_nodes.map do |node|
        desc = node.all_descendants
        total_samples = desc.map(&:samples).sum
        { desc_count: desc.length, name: node.name, file: node.file, line: node.line, samples: total_samples }
      end
    end

    def in_app_nodes
      nodes.select {|n| n.app? }
    end








#     def collapse_tree
#       while true
#         number_changed = collapse_tree_one_level
#         break if number_changed == 0
#       end
#     end
#
#     # For each leaf node, sees if it is internal to the monitored app. If not,
#     # collapse that node to its parents, weighted by the edge counts
#     # If that node was internal to the monitored app, leave it.
#     # Returns 0 if nothing changed, a positive integer if things did change,
#     # indicating how many leaves were collapsed
#     def collapse_tree_one_level
#       number_changed = 0
#
#       puts "===========ITERATION==========="
#       leaves.each do |leaf_node|
#         next if leaf_node.app?
#         puts "Collapsing - #{leaf_node.name}"
#         # app parent: #{leaf_node.self_or_parents_in_app?.map {|x| x.name}}"
#         number_changed += 1
#         leaf_node.collapse_to_parent!
#         @nodes = @nodes.reject { |n| n == leaf_node }
#       end
#
#       number_changed
#     end
#
#     # Returns the final result, an array of hashes
#     def generate_output
#       leaves.map{|x| { name: x.name, samples: x.samples, file: x.file, line: x.line } }
#     end
#
#     # A leaf node has no children.
#     def leaves
#       nodes.find_all { |n| n.children.empty? }
#     end
#

    ###########################################
    # TreeNode class represents a single node.
    ###########################################
    TreeNode = Struct.new(:frame_id, :name, :file, :line, :samples,
                          :children_edges, :children, :parents) do
      def app?
        # file =~ /^#{ScoutApm::Environment.instance.root}/
        @is_app ||= file =~ /releases/
      end

      # My samples, and the weighted samples of all of my children
      def samples_for_self_and_descendants(seen=Set.new)
        viable_children = children.reject(&:app?)
        @samples_for_self_and_descendants ||= samples + viable_children.map{ |c_node|
          if seen.include? self
            puts "I've already seen #{self.name}, bailing"
            return samples # we've already been included, we're looping
          else
            seen << self
            c_node.samples_for_parent(self, seen.dup).tap { |val| puts "Child gave me #{val}" }
          end
        }.sum
      end

      # For this parent of mine, how many of my samples do they get.
      # is combo of "how many samples do I have, and what's the relative weight of this parent"
      def samples_for_parent(p_node, seen=Set.new)
        samples_for_self_and_descendants(seen) * relative_weight_of_parent(p_node)
      end

      def relative_weight_of_parent(p_node)
        total = parents.map{|(_, weight)| weight}.sum
        p_node_weight = parents.detect(0) {|(this_parent, _)| this_parent == p_node }[1]
        p_node_weight.to_f / total.to_f
      end











      # Allocate this node's samples to its parents, in relation to the rate at
      # which each parent called this method.  Then clear the child from each of the parents
      def collapse_to_parent!
        total_weight = parents.map{ |(_, weight)| weight }.inject(0){ |sum, weight| sum + weight }
        parents.each do |(p_node, weight)|
          relative_weight = weight.to_f / total_weight.to_f
          p_node.samples += (samples * relative_weight)
        end

        parents.each {|(p_node, _)| p_node.delete_child!(self) }
      end

      def delete_child!(node)
        self.children = self.children.reject {|c| c == node }
      end

      # Force object_id to be the equality mechanism, rather than struct's
      # default which delegates to == on each value.  That is wrong because
      # we want to be able to dup a node in the tree construction process and
      # not have those compare equal to each other.
      # def ==(other)
        # object_id == other.object_id
      # end

      def inspect
        "#{frame_id}: #{name} - ##{samples}\n" +
        "  Parents: #{parents.map{ |(p, w)| "#{p.name}: #{w}"}.join("\n           ") }\n" +
        "  Children: #{children_edges.inspect} \n"
      end

      def all_descendants(max_depth=100)
        descendants = [self]
        unchecked_edge = self.children.reject(&:app?)
        stop = false

        puts "----------------------------------------"

        while max_depth > 0 && !stop
          before_count = descendants.length

          descendants = (descendants + unchecked_edge).uniq
          unchecked_edge = unchecked_edge.map(&:children).flatten.uniq.reject(&:app?)
          puts "UncheckedEdge Children: #{unchecked_edge.length}"

          after_count = descendants.length
          stop = true if before_count == after_count
          max_depth = max_depth - 1
        end

        puts "#{name} - Found #{descendants.length} children after #{100 - max_depth} iterations"

        puts "----------------------------------------"

        descendants
      end

      #### TreeNode Debug Helpers
      def cycles?(seen=[])
        return true if seen.include? self
        seen << self
        parents.any? {|(p_node, _)| p_node.cycles?(seen.dup) }
      end

      def all_parents_flattened
        all_of_em = []
        all_of_em += parents.map{|(p_node, _)| p_node.all_parents_flattened }
        all_of_em
      end

      def self_or_parents_in_app?(max_depth=200)
        return nil if max_depth == 0

        if app?
          self
        elsif parents.length > 0
          self.parents.find { |(p_node, _)| p_node.self_or_parents_in_app?(max_depth - 1) }.try(:first)
        else
          nil
        end
      end
      #### </debug helpers>

    end
  end
end
