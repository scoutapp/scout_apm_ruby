if defined?(::Net) && defined?(Net::HTTP)
  ScoutApm::Agent.instance.logger.debug "Instrumenting Net::HTTP"
  Net::HTTP.class_eval do
    include ScoutApm::Tracer
    
    def request_with_scout_instruments(*args,&block)
      self.class.instrument("HTTP/request", :desc => "#{(@address+args.first.path.split('?').first)[0..99]}") do
        request_without_scout_instruments(*args,&block)
      end
    end
    alias request_without_scout_instruments request
    alias request request_with_scout_instruments
  end
end
