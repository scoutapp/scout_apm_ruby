module ScoutApm
  class Config   
    DEFAULTS =  {
        'host' => 'https://apm.scoutapp.com',
        'log_level' => 'info'
    }

    def initialize(config_path = nil)
      @config_path = config_path
    end
  
    # Fetch a config value. It first attempts to fetch an ENV var prefixed with 'SCOUT_', then from the settings file.
    def value(key)
      value = ENV['SCOUT_'+key.upcase] || settings[key]
      value.to_s.strip.length.zero? ? nil : value
    end

    private

    def config_path
      @config_path || File.join(ScoutApm::Agent.instance.environment.root,"config","scout_apm.yml")
    end
    
    def config_file
      File.expand_path(config_path)
    end

    def settings
      return @settings if @settings
      load_file
    end
    
    def load_file
      begin
        if !File.exist?(config_file)
          ScoutApm::Agent.instance.logger.warn "No config file found at [#{config_file}]."
          @settings = {}
        else
          @settings = YAML.load(ERB.new(File.read(config_file)).result(binding))[ScoutApm::Agent.instance.environment.env] || {} 
        end  
      rescue Exception => e
        ScoutApm::Agent.instance.logger.warn "Unable to load the config file."
        ScoutApm::Agent.instance.logger.warn e.message
        ScoutApm::Agent.instance.logger.warn e.backtrace
        @settings = {}
      end
      @settings = DEFAULTS.merge(@settings)
    end
  end # Config
end # ScoutApm