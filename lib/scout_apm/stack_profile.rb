require 'stack_profile'

module ScoutApm
  class StackProfile
    attr_reader :gc_events

    ############################
    ###     Class Methods    ###
    ############################

    def self.gc_event_datas_for(start_time, end_time)
      event_datas = []
      gc_event_datas.select{|evnt| (evnt[:end_gc_count] > 0) && times_overlap?(evnt[:start_time], evnt[:end_time], start_time, end_time) }.each do |gc_data_hash|
        event_datas << gc_data_hash
      end
      event_datas
    end

    #            start_time                                       end_time    
    #      Layer      |──────────────────────────────────────────────|        
    #                                                                         
    #  GC Events  |──────────────────────────1───────────────────────────|    
    #                                                                         
    #             |───────2────|                                              
    #                                                                         
    #                       |───────3─────────|                               
    #                                                                         
    #                                                      |────────4────────|
    #                                                                         
    #     1) gc starts before and ends after layer times                      
    #     2) gc starts before layer but ends before layer                     
    #     3) gc starts and ends fully within layer start/end times            
    #     4) gc starts before layer end, but ends after layer end             
    #
    def self.times_overlap?(gc_start_time, gc_end_time, start_time, end_time)
      # GC Event case 1 from diagram
      return true if (start_time > gc_start_time) && (end_time > gc_start_time) && (end_time < gc_end_time)

      # GC Event case 2
      return true if (start_time > gc_start_time) && (start_time < gc_end_time) && (end_time > gc_end_time)

      # GC Event case 3
      return true if (start_time < gc_start_time) && (end_time > gc_end_time)

      # GC Event case 4
      return true if (start_time < gc_start_time) && (end_time > gc_start_time) && (end_time < gc_end_time)

      # Otherwise events do not overlap
      return false
    end

    ############################
    ###   Instance Methods   ###
    ############################
    def initialize(gc_event_datas)
      @gc_event_datas = gc_event_datas
      @gc_events = @gc_event_datas.map{|data| event = ScoutApm::GcEvent.new(data); event.valid? ? event : nil }.compact
    end

    def rss_increased?
       rss_size_diff > 0
    end

    def rss_decreased?
      rss_size_diff < 0
    end

    def rss_size_diff
      @gc_events.inject(0){|total,evnt| total += evnt.rss_size_diff; total}
    end
  end
end
