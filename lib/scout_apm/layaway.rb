# Stores metrics in a file before sending them to the server. Two uses:
# 1. A centralized store for multiple Agent processes. This way, only 1 checkin is sent to Scout rather than 1 per-process.
# 2. Bundling up reports from multiple timeslices to make updates more efficent server-side.
# 
# Data is stored in a Hash, where the keys are Time.to_i on the minute. The value is a Hash {:metrics => Hash, :slow_transactions => Array}.
# When depositing data, the new data is either merged with an existing time or placed in a new key.
class ScoutApm::Layaway
  attr_accessor :file
  def initialize
    @file = ScoutApm::LayawayFile.new
  end
  
  def deposit_and_deliver
    new_metrics = ScoutApm::Agent.instance.store.metric_hash
    log_deposited_metrics(new_metrics)
    log_deposited_slow_transactions(ScoutApm::Agent.instance.store.slow_transactions)
    to_deliver = {}
    file.read_and_write do |old_data|
      old_data ||= Hash.new
      # merge data
      # if (1) there's data in the file and (2) there isn't any data yet for the current minute, this means we've 
      # collected all metrics for the previous slots and we're ready to deliver.
      #
      # Example w/2 processes:
      #
      # 12:00:34 ---
      # Process 1: old_data.any? => false, so deposits.
      # Process 2: old_data_any? => true and old_data[12:00].nil? => false, so deposits. 
      #
      # 12:01:34 ---
      # Process 1: old_data.any? => true and old_data[12:01].nil? => true, so delivers metrics.
      # Process 2: old_data.any? => true and old_data[12:01].nil? => false, so deposits.
      if old_data.any? and old_data[slot].nil?
        to_deliver = old_data
        old_data = Hash.new
      elsif old_data.any?
        ScoutApm::Agent.instance.logger.debug "Not yet time to deliver payload for slot [#{Time.at(old_data.keys.sort.last).strftime("%m/%d/%y %H:%M:%S %z")}]"
      else
        ScoutApm::Agent.instance.logger.debug "There is no data in the layaway file to deliver."
      end
      old_data[slot]=ScoutApm::Agent.instance.store.merge_data_and_clear(old_data[slot] || {:metrics => {}, :slow_transactions => []})
      log_saved_data(old_data,new_metrics)
      old_data
    end
    to_deliver.any? ? validate_data(to_deliver) : {}
  end
  
  # Ensures the data we're sending to the server isn't stale. 
  # This can occur if the agent is collecting data, and app server goes down w/data in the local storage. 
  # When it is restarted later data will remain in local storage but it won't be for the current reporting interval.
  # 
  # If the data is stale, an empty Hash is returned. Otherwise, the data from the most recent slot is returned.
  def validate_data(data)
    data = data.to_a.sort
    now = Time.now
    if (most_recent = data.first.first) < now.to_i - 2*60
      ScoutApm::Agent.instance.logger.debug "Local Storage is stale (#{Time.at(most_recent).strftime("%m/%d/%y %H:%M:%S %z")}). Not sending data."
      {}
    else
      data.first.last
    end
  rescue
    ScoutApm::Agent.instance.logger.debug $!.message
    ScoutApm::Agent.instance.logger.debug $!.backtrace
  end
  
  # Data is stored under timestamp-keys (without the second).
  def slot
    t = Time.now
    t -= t.sec
    t.to_i
  end
  
  def log_deposited_metrics(new_metrics)
    controller_count = 0
    new_metrics.each do |meta,stats|
      if meta.metric_name =~ /\AController/
        controller_count += stats.call_count
      end
    end
    ScoutApm::Agent.instance.logger.debug "Depositing #{controller_count} requests into #{Time.at(slot).strftime("%m/%d/%y %H:%M:%S %z")} slot."
  end

  def log_deposited_slow_transactions(new_slow_transactions)
    ScoutApm::Agent.instance.logger.debug "Depositing #{new_slow_transactions.size} slow transactions into #{Time.at(slot).strftime("%m/%d/%y %H:%M:%S %z")} slot."
  end
  
  def log_saved_data(old_data,new_metrics)
    ScoutApm::Agent.instance.logger.debug "Saving the following #{old_data.size} time slots locally:"
    old_data.each do |k,v|
      controller_count = 0
      new_metrics.each do |meta,stats|
        if meta.metric_name =~ /\AController/
          controller_count += stats.call_count
        end
      end
      ScoutApm::Agent.instance.logger.debug "#{Time.at(k).strftime("%m/%d/%y %H:%M:%S %z")} => #{controller_count} requests and #{v[:slow_transactions].size} slow transactions"
    end
  end
end
