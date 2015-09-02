# Logic for the serialized file access
module ScoutApm
  class LayawayFile
    def path
      "#{ScoutApm::Agent.instance.default_log_path}/scout_apm.db"
    end

    def dump(object)
      Marshal.dump(object)
    end

    def load(dump)
      if dump.size == 0
        ScoutApm::Agent.instance.logger.debug("No data in layaway file.")
        return nil
      end
      Marshal.load(dump)
    rescue ArgumentError, TypeError => e
      ScoutApm::Agent.instance.logger.debug("Error loading data from layaway file: #{e.inspect}")
      ScoutApm::Agent.instance.logger.debug(e.backtrace.inspect)
      nil
    end

    def read_and_write
      File.open(path, File::RDWR | File::CREAT) do |f|
        f.flock(File::LOCK_EX)
        begin
          result = (yield get_data(f))
          f.rewind
          f.truncate(0)
          if result
            write(f, dump(result))
          end
        ensure
          f.flock(File::LOCK_UN)
        end
      end
    rescue Errno::ENOENT, Exception  => e
      ScoutApm::Agent.instance.logger.error("Unable to access the layaway file [#{e.message}]. The user running the app must have read+write access.")
      ScoutApm::Agent.instance.logger.debug(e.backtrace.split("\n"))
      # ensure the in-memory metric hash is cleared so data doesn't continue to accumulate.
      ScoutApm::Agent.instance.store.metric_hash = {}
    end

    def get_data(f)
      data = read_until_end(f)
      result = load(data)
      f.truncate(0)
      result
    end

    def write(f, string)
      result = 0
      while (result < string.length)
        result += f.write_nonblock(string)
      end
    rescue Errno::EAGAIN, Errno::EINTR
      IO.select(nil, [f])
      retry
    end

    def read_until_end(f)
      contents = ""
      while true
        contents << f.read_nonblock(10_000)
      end
    rescue Errno::EAGAIN, Errno::EINTR
      IO.select([f])
      retry
    rescue EOFError
      contents
    end
  end
end
