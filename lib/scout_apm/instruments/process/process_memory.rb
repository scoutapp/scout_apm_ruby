module ScoutApm
  module Instruments
    module Process
      class ProcessMemory
        attr_reader :logger

        def initialize(logger)
          @logger = logger
        end

        def metric_type
          "Memory"
        end

        def metric_name
          "Physical"
        end

        def human_name
          "Process Memory"
        end

        def run
          case RUBY_PLATFORM.downcase
          when /linux/
            get_mem_from_procfile
          when /darwin9/ # 10.5
            get_mem_from_shell("ps -o rsz")
          when /darwin1[0123]/ # 10.6 - 10.10
            get_mem_from_shell("ps -o rss")
          else
            0 # What default? was nil.
          end.tap { |res| logger.debug "#{human_name}: #{res.inspect}" }
        end

        private

        def get_mem_from_procfile
          res = nil
          proc_status = File.open(procfile, "r") { |f| f.read_nonblock(4096).strip }
          if proc_status =~ /RSS:\s*(\d+) kB/i
            res= $1.to_f / 1024.0
          end
          res
        end

        def procfile
          "/proc/#{$$}/status"
        end

        # memory in MB the current process is using
        def get_mem_from_shell(command)
          res = `#{command} #{$$}`.split("\n")[1].to_f / 1024.0 #rescue nil
          res
        end
      end
    end
  end
end
