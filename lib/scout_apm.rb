module ScoutApm
end
require 'socket'
require 'set'
require 'net/http'
require 'logger'
require 'yaml'
require 'cgi'

require File.expand_path('../scout_apm/version.rb', __FILE__)
require File.expand_path('../scout_apm/agent.rb', __FILE__)
require File.expand_path('../scout_apm/agent/logging.rb', __FILE__)
require File.expand_path('../scout_apm/agent/reporting.rb', __FILE__)
require File.expand_path('../scout_apm/layaway.rb', __FILE__)
require File.expand_path('../scout_apm/layaway_file.rb', __FILE__)
require File.expand_path('../scout_apm/config.rb', __FILE__)
require File.expand_path('../scout_apm/background_worker.rb', __FILE__)
require File.expand_path('../scout_apm/environment.rb', __FILE__)
require File.expand_path('../scout_apm/metric_meta.rb', __FILE__)
require File.expand_path('../scout_apm/metric_stats.rb', __FILE__)
require File.expand_path('../scout_apm/stack_item.rb', __FILE__)
require File.expand_path('../scout_apm/store.rb', __FILE__)
require File.expand_path('../scout_apm/tracer.rb', __FILE__)
require File.expand_path('../scout_apm/context.rb', __FILE__)
require File.expand_path('../scout_apm/slow_transaction.rb', __FILE__)
require File.expand_path('../scout_apm/instruments/process/process_cpu.rb', __FILE__)
require File.expand_path('../scout_apm/instruments/process/process_memory.rb', __FILE__)

if defined?(Rails) and Rails.respond_to?(:version) and Rails.version >= '3'
  module ScoutApm
    class Railtie < Rails::Railtie
      initializer "scout_apm.start" do |app|
        ScoutApm::Agent.instance.start
      end
    end
  end
else
  ScoutApm::Agent.instance.start
end

