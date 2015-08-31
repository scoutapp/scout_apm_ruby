module ScoutApm
  module Instruments
    module Process
      class ProcessCpu
        attr_reader :logger
        attr_reader :num_processors
        attr_accessor :last_run, :last_utime, :last_stime


        def initialize(num_processors, logger)
          @num_processors = [num_processors, 1].compact.max
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

          t = ::Process.times
          now = Time.now
          utime = t.utime
          stime = t.stime

          wall_clock_elapsed  = now - last_run

          utime_elapsed   = utime - last_utime
          stime_elapsed   = stime - last_stime
          process_elapsed = utime_elapsed + stime_elapsed

          # Normalized to # of processors
          normalized_wall_clock_elapsed = wall_clock_elapsed * num_processors

          # If somehow we run for 0 seconds between calls, don't try to divide by 0
          res = if normalized_wall_clock_elapsed == 0
                  0
                else
                  ( process_elapsed / normalized_wall_clock_elapsed )*100
                end

          self.last_run = now
          self.last_utime = t.utime
          self.last_stime = t.stime

          logger.debug "#{human_name}: #{res.inspect} [#{Environment.instance.processors} CPU(s)]"

          return res
        end
      end
    end
  end
end
