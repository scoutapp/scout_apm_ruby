module ScoutApm
end

#####################################
# Ruby StdLibrary Requires
#####################################
require 'cgi'
require 'logger'
require 'net/http'
require 'openssl'
require 'set'
require 'socket'
require 'yaml'
require 'thread'

#####################################
# Gem Requires
#####################################
begin
  require 'stackprof'
rescue LoadError
  require 'scout_apm/utils/fake_stack_prof'
end

#####################################
# Internal Requires
#####################################
require 'scout_apm/version'

require 'scout_apm/server_integrations/passenger'
require 'scout_apm/server_integrations/puma'
require 'scout_apm/server_integrations/rainbows'
require 'scout_apm/server_integrations/thin'
require 'scout_apm/server_integrations/unicorn'
require 'scout_apm/server_integrations/webrick'
require 'scout_apm/server_integrations/null'

require 'scout_apm/framework_integrations/rails_2'
require 'scout_apm/framework_integrations/rails_3_or_4'
require 'scout_apm/framework_integrations/sinatra'
require 'scout_apm/framework_integrations/ruby'

require 'scout_apm/instruments/net_http'
require 'scout_apm/instruments/moped'
require 'scout_apm/instruments/mongoid'
require 'scout_apm/instruments/active_record'
require 'scout_apm/instruments/action_controller_rails_2'
require 'scout_apm/instruments/action_controller_rails_3'
require 'scout_apm/instruments/process/process_cpu'
require 'scout_apm/instruments/process/process_memory'

require 'scout_apm/app_server_load'

require 'scout_apm/utils/sql_sanitizer'
require 'scout_apm/utils/null_logger'
require 'scout_apm/utils/installed_gems'
require 'scout_apm/utils/time'

require 'scout_apm/config'
require 'scout_apm/environment'
require 'scout_apm/agent'
require 'scout_apm/agent/logging'
require 'scout_apm/agent/reporting'
require 'scout_apm/layaway'
require 'scout_apm/layaway_file'
require 'scout_apm/reporter'
require 'scout_apm/background_worker'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/stack_item'
require 'scout_apm/store'
require 'scout_apm/tracer'
require 'scout_apm/context'
require 'scout_apm/stackprof_tree_collapser'
require 'scout_apm/slow_transaction'
require 'scout_apm/capacity'

require 'scout_apm/serializers/payload_serializer'
require 'scout_apm/serializers/directive_serializer'
require 'scout_apm/serializers/app_server_load_serializer'

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

