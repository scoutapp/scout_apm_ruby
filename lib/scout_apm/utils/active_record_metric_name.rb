module ScoutApm
  module Utils
    class ActiveRecordMetricName
      DEFAULT_METRIC = "SQL/Unknown"

      attr_reader :sql, :name

      def initialize(sql, name)
        @sql = sql
        @name = name.to_s
      end

      # Converts an SQL string and the name (typically assigned automatically
      # by rails) into a Scout metric_name.
      #
      # sql: SELECT "places".* FROM "places"  ORDER BY "places"."position" ASC
      # name: Place Load
      # metric_name: Place/find
      def to_s
        return DEFAULT_METRIC unless name
        return DEFAULT_METRIC unless model && operation

        if parsed = parse_operation
          "#{model}/#{parsed}"
        else
          "SQL/other"
        end
      end

      def model
        parts.first
      end

      def normalized_operation
        parse_operation
      end

      # For the layer lookup.
      def hash
        h = name.downcase.hash
        h
      end

      # For the layer lookup.
      # Reminder: #eql? is for Hash equality: returns true if obj and other refer to the same hash key.
      def eql?(o)
        self.class    == o.class &&
        name.downcase == o.name.downcase
      end

      alias_method :==, :eql?

      private

      def operation
        if parts.length >= 2
          parts[1].downcase
        end
      end

      def parts
        name.split(" ")
      end

      # Returns nil if no match
      # Returns nil if the operation wasn't under developer control (and hence isn't interesting to report)
      def parse_operation
        case operation
        when 'indexes', 'columns' then nil # not under developer control
        when 'load' then 'find'
        when 'destroy', 'find', 'save', 'create', 'exists' then operation
        when 'update' then 'save'
        else
          if model == 'Join'
            operation
          end
        end
      end
    end
  end
end
