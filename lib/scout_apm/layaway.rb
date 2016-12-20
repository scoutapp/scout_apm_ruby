# Stores StoreReportingPeriod objects in a per-process file before sending them to the server.
# Coordinates a single process to collect up all individual files, merge them, then send.
#
# Each layaway file is named basedir/scout_#{timestamp}_#{pid}.data
#   Where timestamp is in the format:
#   And PID is the process id of the running process
#
module ScoutApm
  class Layaway
    # How long to let a stale file sit before deleting it.
    # Letting it sit a bit may be useful for debugging
    STALE_AGE = 10 * 60

    # Failsafe to prevent writing layaway files if for some reason they are not being cleaned up
    MAX_FILES_LIMIT = 5000

    # A strftime format string for how we render timestamps in filenames.
    # Must be sortable as an integer
    TIME_FORMAT = "%Y%m%d%H%M"

    attr_accessor :config
    attr_reader :environment

    def initialize(config, environment)
      @config = config
      @environment = environment
    end

    # Returns a Pathname object with the fully qualified directory where the layaway files can be placed.
    # That directory must be writable by this process.
    #
    # Don't set this in initializer, since it relies on agent instance existing to figure out the value.
    #
    def directory
      return @directory if @directory

      data_file = config.value("data_file")
      data_file = File.dirname(data_file) if data_file && !File.directory?(data_file)

      candidates = [
        data_file,
        "#{environment.root}/tmp",
        "/tmp"
      ].compact

      found = candidates.detect { |dir| File.writable?(dir) }
      ScoutApm::Agent.instance.logger.debug("Storing Layaway Files in #{found}")
      @directory = Pathname.new(found)
    end

    def write_reporting_period(reporting_period, files_limit = MAX_FILES_LIMIT)
      if at_layaway_file_limit?(files_limit)
        ScoutApm::Agent.instance.logger.error("Hit layaway file limit. Not writing to layaway file")
        return false
      end
      filename = file_for(reporting_period.timestamp)
      layaway_file = LayawayFile.new(filename)
      layaway_file.write(reporting_period)
    end

    # Claims a given timestamp (getting a lock on a particular filename),
    # then yields ReportingPeriods collected up from all the files.
    # If the yield returns truthy, delete the layaway files that made it up.
    def with_claim(timestamp)
      coordinator_file = glob_pattern(timestamp, :coordinator)

      begin
        # This file gets deleted only by a process that successfully created and obtained the exclusive lock
        f = File.open(coordinator_file, File::RDWR | File::CREAT | File::EXCL | File::NONBLOCK)
      rescue Errno::EEXIST
        false
      end

      begin
        if f
          begin
            ScoutApm::Agent.instance.logger.debug("Obtained Reporting Lock")

            log_layaway_file_information

            files = all_files_for(timestamp).reject{|l| l.to_s == coordinator_file.to_s }
            rps = files.map{ |layaway| LayawayFile.new(layaway).load }.compact
            if rps.any?
              yield rps

              ScoutApm::Agent.instance.logger.debug("Deleting the now-reported layaway files for #{timestamp.to_s}")
              delete_files_for(timestamp) # also removes the coodinator_file

              ScoutApm::Agent.instance.logger.debug("Checking for any Stale layaway files")
              delete_stale_files(timestamp.to_time - STALE_AGE)
            else
              File.unlink(coordinator_file)
              ScoutApm::Agent.instance.logger.debug("No layaway files to report")
            end

            true
          rescue Exception => e
            ScoutApm::Agent.instance.logger.debug("Caught an exception in with_claim, with the coordination file locked: #{e.message}, #{e.backtrace.inspect}")
            raise
          ensure
            # Unlock the file when done!
            f.flock(File::LOCK_UN | File::LOCK_NB)
            f.close
          end
        else
          # Didn't obtain lock, another process is reporting. Return false from this function, but otherwise no work
          false
        end
      end
    end

    def delete_files_for(timestamp)
      all_files_for(timestamp).each { |layaway|
        ScoutApm::Agent.instance.logger.debug("Deleting layaway file: #{layaway}")
        File.unlink(layaway)
      }
    end

    def delete_stale_files(older_than)
      all_files_for(:all).
        map { |filename| timestamp_from_filename(filename) }.
        compact.
        uniq.
        select { |timestamp| timestamp.to_i < older_than.strftime(TIME_FORMAT).to_i }.
          tap  { |timestamps| ScoutApm::Agent.instance.logger.debug("Deleting stale layaway files with timestamps: #{timestamps.inspect}") }.
        map    { |timestamp| delete_files_for(timestamp) }
    rescue => e
      ScoutApm::Agent.instance.logger.debug("Problem deleting stale files: #{e.message}, #{e.backtrace.inspect}")
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

    def at_layaway_file_limit?(files_limit = MAX_FILES_LIMIT)
      all_files_for(:all).count >= files_limit
    end

    def log_layaway_file_information
      files_in_temp = Dir["#{directory}/*"].count

      all_filenames = all_files_for(:all)
      count_per_timestamp = Hash[
        all_filenames.
        group_by {|f| timestamp_from_filename(f) }.
        map{ |timestamp, list| [timestamp, list.length] }
      ]


      ScoutApm::Agent.instance.logger.debug("Total in #{directory}: #{files_in_temp}. Total Layaway Files: #{all_filenames.size}.  By Timestamp: #{count_per_timestamp.inspect}")
    end
  end
end

