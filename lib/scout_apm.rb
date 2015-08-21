module ScoutApm
end

require 'cgi'
require 'logger'
require 'net/http'
require 'openssl'
require 'set'
require 'socket'
require 'yaml'

require 'scout_apm/version'
require 'scout_apm/utils/sql_sanitizer'
require 'scout_apm/utils/null_logger'
require 'scout_apm/agent'
require 'scout_apm/agent/logging'
require 'scout_apm/agent/reporting'
require 'scout_apm/layaway'
require 'scout_apm/layaway_file'
require 'scout_apm/config'
require 'scout_apm/background_worker'
require 'scout_apm/environment'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/stack_item'
require 'scout_apm/store'
require 'scout_apm/tracer'
require 'scout_apm/context'
require 'scout_apm/slow_transaction'
require 'scout_apm/capacity'
require 'scout_apm/instruments/process/process_cpu'
require 'scout_apm/instruments/process/process_memory'

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

