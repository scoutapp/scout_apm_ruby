module ScoutApm
  class SlowTransaction
    BACKTRACE_THRESHOLD = 0.5 # the minimum threshold to record the backtrace for a metric.
    BACKTRACE_LIMIT = 5 # Max length of callers to display
    MAX_SIZE = 100 # Limits the size of the metric hash to prevent a metric explosion.

    attr_reader :metric_name, :total_call_time, :metrics, :meta, :uri, :context, :time, :prof

    # Given a call stack, generates a filtered backtrace that:
    # * Limits to the app/models, app/controllers, or app/views directories
    # * Limits to 5 total callers
    # * Makes the app folder the top-level folder used in trace info
    def self.backtrace_parser(backtrace)
      stack = []
      backtrace.each do |c|
        if m=c.match(/(\/app\/(controllers|models|views)\/.+)/)
          stack << m[1]
          break if stack.size == BACKTRACE_LIMIT
        end
      end
      stack
    end

    def initialize(uri, metric_name, total_call_time, metrics, context, time, prof)
      @uri = uri
      @metric_name = metric_name
      @total_call_time = total_call_time
      @metrics = metrics
      @context = context
      @time = time
      ScoutApm::Agent.instance.logger.debug("PROF: #{prof}")
      @prof = parse_prof(prof)
      ScoutApm::Agent.instance.logger.debug("PostProcessed PROF: #{prof}")

    end

    # Used to remove metrics when the payload will be too large.
    def clear_metrics!
      @metrics = nil
      self
    end

    TreeNode = Struct.new(:frame_id, :name, :file, :line, :samples,
                          :children_edges, :children, :parents) do
      def app?
        file =~ /^#{ScoutApm::Environment.instance.root}/
      end

      def ==(other)
        object_id == other.object_id
      end
    end

    def parse_prof(data)
      nodes = data[:frames].map do |(frame_id, frame_data)|
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

      nodes.each do |node|
        children = nodes.find_all { |n| node.children_edges.keys.include? n.frame_id }

        node.children_edges.each do |(frame_id, weight)|
          child = children.detect{ |c| c.frame_id == frame_id }
          child.parents << [node, weight]
        end

        node.children = children
      end

      while true
        number_changed = 0

        leaves(nodes).each do |leaf_node|

          if ! leaf_node.app?
            number_changed += 1

            # Allocate to parents
            total_weight = leaf_node.parents.map{ |p| p[1] }.inject(0){ |sum, weight| sum + weight }
            leaf_node.parents.each do |(p_node, weight)|
              relative_weight = weight.to_f / total_weight.to_f
              p_node.samples += (leaf_node.samples * relative_weight)
            end

            # Remove this node from the tree structure
            leaf_node.parents.each {|(p_node, _)| p_node.children.delete(leaf_node) }
            nodes.delete(leaf_node)
          end
        end

        break if number_changed == 0
      end

      leaves(nodes).map{|x| { name: x.name, samples: x.samples, file: x.file, line: x.line } }
    end

    def leaves(node_list)
      node_list.find_all { |n| n.children.empty? }
    end
  end
end
