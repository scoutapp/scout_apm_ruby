require 'stack_profile'

class StackProfile
    attr_reader :gc_data

    def rss_increased?
      @gc_data[:end_max_rss] > @gc_data[:start_max_rss]
    end

    def gc_ended_between?(start_time, stop_time)
      start_time < @gc_data[:end_time] && @gc_data[:end_time] < stop_time
    end
end

ScoutApm.after_gc_start_hook = proc { p "GC START"}
ScoutApm.after_gc_end_hook = proc { p "GC END"}