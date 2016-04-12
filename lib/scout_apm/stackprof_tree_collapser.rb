module ScoutApm
  class StackprofTreeCollapser
    attr_reader :raw_stackprof
    attr_reader :nodes

    def initialize(raw_stackprof)
      @raw_stackprof = raw_stackprof

      # Log the raw stackprof info
      #unless StackProf.respond_to?(:fake?) && StackProf.fake?
      #  begin
      #    ScoutApm::Agent.instance.logger.debug("StackProf - Samples: #{raw_stackprof[:samples]}, GC: #{raw_stackprof[:gc_samples]}, missed: #{raw_stackprof[:missed_samples]}, Interval: #{raw_stackprof[:interval]}")
      #  rescue
      #    ScoutApm::Agent.instance.logger.debug("StackProf Raw - #{raw_stackprof.inspect}")
      #  end
      #end
    end

    def call
      build_tree
      connect_children
      total_samples_of_app_nodes
    rescue
      []
    end

    private

    def build_tree
      @nodes = raw_stackprof[:frames].map do |(frame_id, frame_data)|
        TreeNode.new(frame_id,                     # frame_id
                     frame_data[:name],            # name
                     frame_data[:file],            # file
                     frame_data[:line],            # line
                     frame_data[:samples],         # samples
                     frame_data[:total_samples],   # total_samples
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

    def in_app_nodes
      nodes.select {|n| n.app? }
    end

    def total_samples_of_app_nodes
      in_app_nodes.reject{|n| n.calls_only_app_nodes? && !n.has_samples? }.
        map{|n| { :samples => n.total_samples,
                  :name => n.name,
                  :file => n.file,
                  :line => n.line
                }
        }
    end

    ###########################################
    # TreeNode class represents a single node.
    ###########################################
    TreeNode = Struct.new(:frame_id, :name, :file, :line, :samples, :total_samples,
                          :children_edges, :children, :parents) do
      def app?
        @is_app ||= file =~ /^#{ScoutApm::Environment.instance.root}/
      end

      # Force object_id to be the equality mechanism, rather than struct's
      # default which delegates to == on each value.  That is wrong because
      # we want to be able to dup a node in the tree construction process and
      # not have those compare equal to each other.
      def ==(other)
        object_id == other.object_id
      end

      def inspect
        "#{frame_id}: #{name} - ##{samples}\n" +
        "  Parents: #{parents.map{ |(p, w)| "#{p.name}: #{w}"}.join("\n           ") }\n" +
        "  Children: #{children_edges.inspect} \n"
      end

      def calls_only_app_nodes?
        children.all?(&:app?)
      end

      def has_samples?
        samples > 0
      end
    end
  end
end
