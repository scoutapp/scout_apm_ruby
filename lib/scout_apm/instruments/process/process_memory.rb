module ScoutApm
  module Instruments
    module Process
      class ProcessMemory
        def run
          res=nil
          platform = RUBY_PLATFORM.downcase

          if platform =~ /linux/
            res = get_mem_from_procfile
          elsif platform =~ /darwin9/ # 10.5
            res = get_mem_from_shell("ps -o rsz")
          elsif platform =~ /darwin1[01]/ # 10.6 & 10.7
            res = get_mem_from_shell("ps -o rss")
          end
          return res
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
