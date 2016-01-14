require 'test_helper'
require 'scout_apm/agent'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/context'
require 'scout_apm/store'

class AgentTest < Minitest::Test

  # Safeguard to ensure the main agent thread doesn't have any interaction with the layaway file. Contention on file locks can cause delays.
  def test_start_with_lock_on_layaway_file
    # setup the file, putting a lock on it.
    File.open(DATA_FILE_PATH, "w") {}
    f = File.open(DATA_FILE_PATH, File::RDWR | File::CREAT)
    f.flock(File::LOCK_EX)

    agent = ScoutApm::Agent.instance

    no_timeout = true
    begin
      Timeout::timeout(3) { agent.start({:monitor => true, :force => true}) }
    rescue Timeout::Error
      no_timeout = false
    ensure
      f.flock(File::LOCK_UN)
      f.close
    end
    assert no_timeout, "Agent took >= 3s to start. Possible file lock issue."
  end

  def test_reset_file_with_old_format
    File.open(DATA_FILE_PATH, 'w') { |file| file.write(Marshal.dump(OLD_FORMAT)) }
    begin
      ScoutApm::Agent.instance(:force => true).process_metrics
    rescue NoMethodError
      # The agent will raise an exception the first time metrics are processed for scout_apm < 1.2.
      #
      #  NoMethodError: undefined method `values' for []:Array
      # /Users/dlite/projects/scout_apm_ruby/lib/scout_apm/layaway.rb:46:in `periods_ready_for_delivery'
      # /Users/dlite/projects/scout_apm_ruby/lib/scout_apm/agent/reporting.rb:31:in `report_to_server'
      # /Users/dlite/projects/scout_apm_ruby/lib/scout_apm/agent/reporting.rb:24:in `process_metrics'
      # /Users/dlite/projects/scout_apm_ruby/test/unit/layaway_test.rb:27:in `test_reset_file_with_old_format'
    end
    # Data will be fine the next go-around
    no_error = true
    begin
      ScoutApm::Agent.instance(:force => true).process_metrics
    rescue Exception => e
      no_error = false
    end
    assert no_error, "Error trying to process metrics after upgrading from < 1.2 data format: #{e.message if e}"
  end

  ## TODO - adds tests to ensure other potentially long-running things don't sneak in, like HTTP calls.

  OLD_FORMAT = {1452533280 => {:metrics => {}, :slow_transactions => {}} } # Pre 1.2 agents used a different file format to store data. 
end
