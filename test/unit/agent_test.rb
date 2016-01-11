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
    f=File.open(DATA_FILE_PATH, File::RDWR | File::CREAT)
    f.flock(File::LOCK_EX)

    agent = ScoutApm::Agent.instance

    no_timeout = true
    begin
      Timeout::timeout(3) { agent.start({:monitor => true,:force => true}) }
    rescue Timeout::Error
      no_timeout = false
    ensure
      f.flock(File::LOCK_UN)
      f.close
    end
    assert no_timeout, "Agent took >= 3s to start. Possible file lock issue."
  end

  ## TODO - adds tests to ensure other potentially long-running things don't sneak in, like HTTP calls.
end