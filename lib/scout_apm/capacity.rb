# Encapsulates logic for determining capacity utilization of the Ruby processes.
class ScoutApm::Capacity
	attr_reader :processing_start_time, :accumulated_time, :transaction_entry_time

	def initialize
		@processing_start_time = Time.now
		@lock ||= Mutex.new # the transaction_entry_time could be modified while processing a request or when #process is called.
		@accumulated_time = 0.0
	end
	
	# Called when a transaction is traced.
	def start_transaction!
		@lock.synchronize do
			@transaction_entry_time = Time.now
		end
	end

	# Called when a transaction completes to record its time used.
	def finish_transaction!
		@lock.synchronize do
			@accumulated_time += (Time.now - transaction_entry_time).to_f
			@transaction_entry_time = nil
			ScoutApm::Agent.instance.logger.debug "Accumulated time spent process requests: #{accumulated_time}"
		end
	end

	# Ran when sending metrics to server. Reports capacity usage metrics.
	def process
		process_time = Time.now
		ScoutApm::Agent.instance.logger.debug "Processing capacity usage for [#{@processing_start_time}] to [#{process_time}]. Time Spent: #{@accumulated_time}."
		@lock.synchronize do
			time_spent = @accumulated_time
			@accumulated_time = 0.0
			# If a transaction is still running, capture its running time up to now and 
			# reset the +transaction_entry_time+ to now. 
			if @transaction_entry_time
				time_spent += (process_time - @transaction_entry_time).to_f
				ScoutApm::Agent.instance.logger.debug "A transaction is running while calculating capacity. Start time: [#{transaction_entry_time}]. Will update the entry time to [#{process_time}]."
				@transaction_entry_time = process_time # prevent from over-counting capacity usage. update the transaction start time to now.
			end
			time_spent = 0.0 if time_spent < 0.0

			window = (process_time - processing_start_time).to_f # time period we are evaulating capacity usage.
			window = 1.0 if window <= 0.0 # prevent divide-by-zero if clock adjusted.
			capacity = time_spent / window
			ScoutApm::Agent.instance.logger.debug "Instance/Capacity: #{capacity}"
			ScoutApm::Agent.instance.store.track!("Instance/Capacity",capacity,:scope => nil)
			@processing_start_time = process_time
		end
	end
end