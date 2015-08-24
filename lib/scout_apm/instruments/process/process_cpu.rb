module ScoutApm
  module Instruments
    module Process
      class ProcessCpu
        attr_reader :logger

        def initialize(num_processors, logger)
          @num_processors = num_processors || 1
          @logger = logger

          t = ::Process.times
          @last_run = Time.now
          @last_utime = t.utime
          @last_stime = t.stime
        end

        def metric_name
          "CPU/Utilization"
        end

        def human_name
          "Process CPU"
        end

        def run
          res = nil
          now = Time.now
          t = ::Process.times
          if @last_run
            elapsed_time = now - @last_run
            if elapsed_time >= 1
              user_time_since_last_sample = t.utime - @last_utime
              system_time_since_last_sample = t.stime - @last_stime
              res = ((user_time_since_last_sample + system_time_since_last_sample)/(elapsed_time * @num_processors))*100
            end
          end
          @last_utime = t.utime
          @last_stime = t.stime
          @last_run = now

          logger.debug "#{human_name}: #{res.inspect} [#{Environment.instance.processors} CPU(s)]"

          return res
        end
      end
    end
  end
end
