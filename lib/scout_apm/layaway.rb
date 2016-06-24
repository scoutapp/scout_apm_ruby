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

    # How long to let a stale file sit before deleting it.
    # Letting it sit a bit may be useful for debugging
    STALE_AGE = 10 * 60

    # A strftime format string for how we render timestamps in filenames.
    # Must be sortable as an integer
    TIME_FORMAT = "%Y%m%d%H%M"

    def initialize(directory=nil)
      @directory = directory
    end

    # Returns a Pathname object with the fully qualified directory where the layaway files can be placed.
    # That directory must be writable by this process.
    #
    # Don't set this in initializer, since it relies on agent instance existing to figure out the value.
    #
    def directory
      return @directory if @directory

      data_file = ScoutApm::Agent.instance.config.value("data_file")
      data_file = File.dirname(data_file) if data_file && !File.directory?

      candidates = [
        data_file,
        "#{ScoutApm::Agent.instance.environment.root}/tmp",
        "/tmp"
      ].compact

      found = candidates.detect { |dir| File.writable?(dir) }
      ScoutApm::Agent.instance.logger.debug("Storing Layaway Files in #{found}")
      @directory = Pathname.new(found)
    end

    def write_reporting_period(reporting_period)
      filename = file_for(reporting_period.timestamp)
      layaway_file = LayawayFile.new(filename)
      layaway_file.write(reporting_period)
    end

    # Claims a given timestamp (getting a lock on a particular filename),
    # then yields ReportingPeriods collected up from all the files.
    # If the yield returns truthy, delete the layaway files that made it up.
    def with_claim(timestamp)
      coordinator_file = glob_pattern(timestamp, :coordinator)


      # This file gets deleted only by a process that successfully obtained a lock
      f = File.open(coordinator_file, File::RDWR | File::CREAT)
      begin
        # Nonblocking, Exclusive lock.
        if f.flock(File::LOCK_EX | File::LOCK_NB)

          ScoutApm::Agent.instance.logger.debug("Obtained Reporting Lock")

          files = all_files_for(timestamp).reject{|l| l.to_s == coordinator_file.to_s }
          rps = files.map{ |layaway| LayawayFile.new(layaway).load }.compact
          if rps.any?
            yield rps

            delete_files_for(timestamp) # also removes the coodinator_file
            delete_stale_files(timestamp.to_time - STALE_AGE)
          else
            File.unlink(coordinator_file)
            ScoutApm::Agent.instance.logger.debug("No layaway files to report")
          end

          # Unlock the file when done!
          f.flock(File::LOCK_UN | File::LOCK_NB)
          f.close
          true
        else
          # Didn't obtain lock, another process is reporting. Return false from this function, but otherwise no work
          f.close
          false
        end
      end
    end

    def delete_files_for(timestamp)
      all_files_for(timestamp).each { |layaway| File.unlink(layaway) }
    end

    def delete_stale_files(older_than)
      all_files_for(:all).
        map { |filename| timestamp_from_filename(filename) }.
        compact.
        uniq.
        select { |timestamp| timestamp.to_i < older_than.strftime(TIME_FORMAT).to_i }.
          tap  { |timestamps| ScoutApm::Agent.instance.logger.debug("Deleting stale layaway files with timestamps: #{timestamps.inspect}") }.
        map    { |timestamp| delete_files_for(timestamp) }
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
      elsif timestamp.respond_to?(:strftime)
        timestamp.strftime(TIME_FORMAT)
      else
        timestamp.to_s
      end
    end

    def format_pid(pid)
      if pid == :all
        "*"
      else
        pid.to_s
      end
    end

    def timestamp_from_filename(filename)
      match = filename.match(%r{scout_(.*)_.*\.data})
      if match
        match[1]
      else
        nil
      end
    end
  end
end

