module ScoutApm
end

#####################################
# Ruby StdLibrary Requires
#####################################
require 'cgi'
require 'logger'
require 'net/http'
require 'openssl'
require 'pp'
require 'set'
require 'socket'
require 'thread'
require 'time'
require 'yaml'

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

require 'scout_apm/tracked_request'
require 'scout_apm/layer'
require 'scout_apm/request_manager'
require 'scout_apm/layer_converter'
require 'scout_apm/request_queue_time'

require 'scout_apm/server_integrations/passenger'
require 'scout_apm/server_integrations/puma'
require 'scout_apm/server_integrations/rainbows'
require 'scout_apm/server_integrations/thin'
require 'scout_apm/server_integrations/unicorn'
require 'scout_apm/server_integrations/webrick'
require 'scout_apm/server_integrations/null'

require 'scout_apm/background_job_integrations/sidekiq'
require 'scout_apm/background_job_integrations/delayed_job'

require 'scout_apm/framework_integrations/rails_2'
require 'scout_apm/framework_integrations/rails_3_or_4'
require 'scout_apm/framework_integrations/sinatra'
require 'scout_apm/framework_integrations/ruby'

require 'scout_apm/platform_integrations/heroku'
require 'scout_apm/platform_integrations/cloud_foundry'
require 'scout_apm/platform_integrations/server'

require 'scout_apm/deploy_integrations/capistrano_3'
#require 'scout_apm/deploy_integrations/capistrano_2'

require 'scout_apm/instruments/net_http'
require 'scout_apm/instruments/moped'
require 'scout_apm/instruments/mongoid'
require 'scout_apm/instruments/delayed_job'
require 'scout_apm/instruments/active_record'
require 'scout_apm/instruments/action_controller_rails_2'
require 'scout_apm/instruments/action_controller_rails_3_rails4'
require 'scout_apm/instruments/middleware_summary'
# require 'scout_apm/instruments/middleware_detailed' # Currently disabled functionality, see the file for details.
require 'scout_apm/instruments/rails_router'
require 'scout_apm/instruments/sinatra'
require 'scout_apm/instruments/process/process_cpu'
require 'scout_apm/instruments/process/process_memory'

require 'scout_apm/app_server_load'

require 'scout_apm/utils/sql_sanitizer'
require 'scout_apm/utils/active_record_metric_name'
require 'scout_apm/utils/null_logger'
require 'scout_apm/utils/installed_gems'
require 'scout_apm/utils/time'
require 'scout_apm/utils/unique_id'

require 'scout_apm/config'
require 'scout_apm/environment'
require 'scout_apm/agent'
require 'scout_apm/agent/logging'
require 'scout_apm/agent/reporting'
require 'scout_apm/layaway'
require 'scout_apm/layaway_file'
require 'scout_apm/reporter'
require 'scout_apm/background_worker'
require 'scout_apm/bucket_name_splitter'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/stack_item'
require 'scout_apm/store'
require 'scout_apm/tracer'
require 'scout_apm/context'
require 'scout_apm/stackprof_tree_collapser'
require 'scout_apm/slow_transaction'
require 'scout_apm/slow_request_policy'
require 'scout_apm/slow_transaction_set'
require 'scout_apm/capacity'
require 'scout_apm/attribute_arranger'

require 'scout_apm/serializers/payload_serializer'
require 'scout_apm/serializers/payload_serializer_to_json'
require 'scout_apm/serializers/directive_serializer'
require 'scout_apm/serializers/app_server_load_serializer'
require 'scout_apm/serializers/deploy_serializer'

require 'scout_apm/middleware'
require 'scout_apm/gc_event'
require 'scout_apm/stack_profile'

if defined?(Rails) && defined?(Rails::VERSION) && defined?(Rails::VERSION::MAJOR) && Rails::VERSION::MAJOR >= 3 && defined?(Rails::Railtie)
  module ScoutApm
    class Railtie < Rails::Railtie
      initializer "scout_apm.start" do |app|
        # attempt to start on first-request if not otherwise started, which is
        # a good catch-all for Webrick, and Passenger and similar, where we
        # can't detect the running app server until actual requests come in.
        app.middleware.use ScoutApm::Middleware

        # Attempt to start right away, this will work best for preloading apps, Unicorn & Puma & similar
        ScoutApm::Agent.instance.start

      end
    end
  end
else
  ScoutApm::Agent.instance.start
end

