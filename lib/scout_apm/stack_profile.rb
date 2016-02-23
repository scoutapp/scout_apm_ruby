require 'stack_profile'

module ScoutApm
  class StackProfile
      attr_reader :gc_data

      def rss_increased?
        return false unless @gc_data
        @gc_data[:end_max_rss] > @gc_data[:start_max_rss]
      end

      def gc_ended_between?(start_time, stop_time)
        return false unless @gc_data
        start_time < @gc_data[:end_time] and stop_time > @gc_data[:start_time]
      end

      def self.gc_event_array
        @@gc_event_array
      end
  end
end

ScoutApm.after_gc_start_hook = proc { p "GC START"}
ScoutApm.after_gc_end_hook = proc { p "GC END"}