# Used to run a given task every 60 seconds.
module ScoutApm
  class BackgroundWorker
    # in seconds, time between when the worker thread wakes up and runs.
    DEFAULT_PERIOD = 60

    attr_reader :period

    def initialize(period=DEFAULT_PERIOD)
      @period = period
      @keep_running = true
    end

    def stop
      @keep_running = false
    end

    # Runs the task passed to +start+ once.
    def run_once
      @task.call if @task
    end

    # Starts running the passed block every 60 seconds (starting now).
    def start(&block)
      @task = block
      begin
        ScoutApm::Agent.instance.logger.debug "Starting Background Worker, running every #{period} seconds"
        next_time = Time.now
        while @keep_running do
          now = Time.now
          while now < next_time
            sleep_time = next_time - now
            sleep(sleep_time) if sleep_time > 0
            now = Time.now
          end
          @task.call
          while next_time <= now
            next_time += period
          end
        end
      rescue
        ScoutApm::Agent.instance.logger.debug "Background Worker Exception!!!!!!!"
        ScoutApm::Agent.instance.logger.debug $!.message
        ScoutApm::Agent.instance.logger.debug $!.backtrace
      end
    end
  end
end
