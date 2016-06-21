# A single layaway file.  See Layaway for the management of the group of files.
#
# TODO: Should we lock during read or write?
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



#     def path
#       return @path if @path
# 
#       candidates = [
#         ScoutApm::Agent.instance.config.value("data_file"),
#         "#{ScoutApm::Agent.instance.default_log_path}/scout_apm.db",
#         "#{ScoutApm::Agent.instance.environment.root}/tmp/scout_apm.db"
#       ]
# 
#       candidates.each do |candidate|
#         next if candidate.nil?
# 
#         begin
#           ScoutApm::Agent.instance.logger.debug("Checking Layaway File Location: #{candidate}")
#           File.open(candidate, "w") { |f| } # Open & Close to check that we can
# 
#           # No exception, it is valid
#           ScoutApm::Agent.instance.logger.info("Layaway File location found: #{candidate}")
#           @path = candidate
#           return @path
#         rescue Exception
#           ScoutApm::Agent.instance.logger.debug("Couldn't open layaway file for test write at #{candidate}")
#         end
#       end
# 
#       ScoutApm::Agent.instance.logger.error("No valid layaway file found, please set a location in the configuration key `data_file`")
#       nil
#     end
# 
#     def dump(object)
#       Marshal.dump(object)
#     end
# 
#     def load(dump)
#       if dump.size == 0
#         ScoutApm::Agent.instance.logger.debug("No data in layaway file.")
#         return nil
#       end
#       Marshal.load(dump)
#     rescue NameError, ArgumentError, TypeError => e
#       ScoutApm::Agent.instance.logger.info("Unable to load data from Layaway file, resetting.")
#       ScoutApm::Agent.instance.logger.debug("#{e.message}, #{e.backtrace.join("\n\t")}")
#       nil
#     end
# 
#     def read_and_write
#       File.open(path, File::RDWR | File::CREAT) do |f|
#         f.flock(File::LOCK_EX)
#         begin
#           result = (yield get_data(f))
#           f.rewind
#           f.truncate(0)
#           if result
#             write(f, dump(result))
#           end
#         ensure
#           f.flock(File::LOCK_UN)
#         end
#       end
#     rescue Errno::ENOENT, Exception  => e
#       ScoutApm::Agent.instance.logger.error("Unable to access the layaway file [#{e.class} - #{e.message}]. " +
#                                             "The user running the app must have read & write access. " +
#                                             "Change the path by setting the `data_file` key in scout_apm.yml"
#                                            )
#       ScoutApm::Agent.instance.logger.debug(e.backtrace.join("\n\t"))
# 
#       # ensure the in-memory metric hash is cleared so data doesn't continue to accumulate.
#       # ScoutApm::Agent.instance.store.metric_hash = {}
#     end
# 
#     def get_data(f)
#       data = read_until_end(f)
#       result = load(data)
#       f.truncate(0)
#       result
#     end
# 
#     def write(f, string)
#       result = 0
#       while (result < string.length)
#         result += f.write_nonblock(string)
#       end
#     rescue Errno::EAGAIN, Errno::EINTR
#       IO.select(nil, [f])
#       retry
#     end
# 
#     def read_until_end(f)
#       contents = ""
#       while true
#         contents << f.read_nonblock(10_000)
#       end
#     rescue Errno::EAGAIN, Errno::EINTR
#       IO.select([f])
#       retry
#     rescue EOFError
#       contents
#     end
#   end
# end
