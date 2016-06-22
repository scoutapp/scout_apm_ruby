# A single layaway file.  See Layaway for the management of the group of files.
module ScoutApm
  class LayawayFile
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def load
      data = File.open(path, "r") { |f| read_raw(f) }
      deserialize(data)
    rescue NameError, ArgumentError, TypeError => e
      # Marshal error
      ScoutApm::Agent.instance.logger.info("Unable to load data from Layaway file, resetting.")
      ScoutApm::Agent.instance.logger.debug("#{e.message}, #{e.backtrace.join("\n\t")}")
      nil
    end

    def write(data)
      serialized_data = serialize(data)
      File.open(path, "w") { |f| write_raw(f, serialized_data) }
    end

    def serialize(data)
      Marshal.dump(data)
    end

    def deserialize(data)
      Marshal.load(data)
    end

    def read_raw(f)
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

    def write_raw(f, data)
      result = 0
      while (result < data.length)
        result += f.write_nonblock(data)
      end
    rescue Errno::EAGAIN, Errno::EINTR
      IO.select(nil, [f])
      retry
    end
  end
end

