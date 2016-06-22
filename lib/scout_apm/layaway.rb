# Stores StoreReportingPeriod objects in a per-process file before sending them to the server.
# Coordinates a single process to collect up all individual files, merge them, then send.
#
# Each layaway file is named basedir/scout_#{timestamp}_#{pid}.data
#   Where timestamp is in the format:
#   And PID is the process id of the running process
#
module ScoutApm
  class Layaway
    # How old a file needs to be in Seconds before it gets reported.
    REPORTING_AGE = 120

    def initialize(directory=nil)
      @directory = directory
    end

    # Fully qualified directory where the layaway files can be placed. Must be
    # writable by this process.
    # Don't set this in initializer, since it relies on agent instance existing.
    # TODO: Find a location for the in a more intelligent way
    def directory
      default = "#{ScoutApm::Agent.instance.environment.root}/tmp"
      @directory ||= Pathname.new(default)
    end

    def write_reporting_period(reporting_period)
      filename = file_for(reporting_period.timestamp)
      layaway_file = LayawayFile.new(filename)
      layaway_file.write(reporting_period)
    end

    # Claims a given timestamp, then yields ReportingPeriods collected up from all the files.
    # If the yield returns truthy, delete the layaway files that made it up.
    def with_claim(timestamp)
      coordinator_file = glob_pattern(timestamp, :coordinator)
      File.open(coordinator_file, File::RDWR | File::CREAT) do |f|
        begin
          # Exclusive lock.
          # Don't block if some other process holds this lock.
          if f.flock(File::LOCK_EX | File::LOCK_NB)

            files = all_files_for(timestamp).reject{|l| l.to_s == coordinator_file.to_s }
            rps = files.map{ |layaway| LayawayFile.new(layaway).load }
            if rps.any?
              if yield rps
                delete_files_for(timestamp)
              end
            else
              ScoutApm::Agent.instance.logger.debug("No layaway files to report")
            end

          else
            # Couldn't obtain lock. Return false from this function, but otherwise no work
            return false
          end
        ensure
          # Unlock even if we didn't obtain the lock. No harm.
          f.flock(File::LOCK_UN)
        end
      end
    end

    def delete_files_for(timestamp)
      all_files_for(timestamp).each { |layaway| File.unlink(layaway) }
    end

    private

    ##########################################
    # Looking up files

    def file_for(timestamp)
      glob_pattern(timestamp)
    end

    def all_files_for(timestamp)
      Dir[glob_pattern(timestamp, :all)]
    end

    # Timestamp should be either :all or a Time-ish object that responds to strftime (StoreReportingPeriodTimestamp does)
    # if timestamp == :all then find all timestamps, otherwise format it.
    # if pid == :all, get the files for all
    def glob_pattern(timestamp, pid=$$)
      timestamp_pattern = format_timestamp(timestamp)
      pid_pattern = format_pid(pid)
      directory + "scout_#{timestamp_pattern}_#{pid_pattern}.data"
    end

    def format_timestamp(timestamp)
      if timestamp == :all
        "*"
      else
        timestamp.strftime("%Y%m%d%H%M")
      end
    end

    def format_pid(pid)
      if pid == :all
        "*"
      else
        pid.to_s
      end
    end

    # Find all times across all files (returned as strings) in the files we can see
    def file_times
      Dir[glob_pattern(:all, :all)].
        map { |name| name.match(/scout_(.*)_.*data/) }.
        reject {|matchdata| matchdata.nil? }.
        map { |matchdata| matchdata[1] }.
        uniq
    end

    # TODO: I don't trust this parse, since I don't specify the format.
    # Parsed version of file_times
    def parsed_file_times
      file_times.
        map {|ts| Time.parse(ts) }
    end
  end
end

