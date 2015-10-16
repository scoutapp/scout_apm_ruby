require 'singleton'

# Used to retrieve environment information for this application.
module ScoutApm
  class Environment
    include Singleton

    # I've put Thin and Webrick last as they are often used in development and included in Gemfiles
    # but less likely used in production.
    STDOUT_LOGGER = begin
                      l = Logger.new(STDOUT)
                      l.level = Agent.instance.config.value("log_level", true) || Logger::INFO
                    end

    SERVER_INTEGRATIONS = [
      ScoutApm::ServerIntegrations::Passenger.new(STDOUT_LOGGER),
      ScoutApm::ServerIntegrations::Unicorn.new(STDOUT_LOGGER),
      ScoutApm::ServerIntegrations::Rainbows.new(STDOUT_LOGGER),
      ScoutApm::ServerIntegrations::Puma.new(STDOUT_LOGGER),
      ScoutApm::ServerIntegrations::Thin.new(STDOUT_LOGGER),
      ScoutApm::ServerIntegrations::Webrick.new(STDOUT_LOGGER),
      ScoutApm::ServerIntegrations::Null.new(STDOUT_LOGGER), # must be last
    ]

    FRAMEWORK_INTEGRATIONS = [
      ScoutApm::FrameworkIntegrations::Rails2.new,
      ScoutApm::FrameworkIntegrations::Rails3Or4.new,
      ScoutApm::FrameworkIntegrations::Sinatra.new,
      ScoutApm::FrameworkIntegrations::Ruby.new, # Fallback if none match
    ]

    DEPLOY_INTEGRATIONS = [
      ScoutApm::DeployIntegrations::Capistrano3.new(STDOUT_LOGGER),
      # ScoutApm::DeployIntegrations::Capistrano2.new(STDOUT_LOGGER),
    ]

    def env
      @env ||= deploy_integration? ? deploy_integration.env : framework_integration.env
    end

    def framework
      framework_integration.name
    end

    def framework_integration
      @framework ||= FRAMEWORK_INTEGRATIONS.detect{ |integration| integration.present? }
    end

    def application_name
      Agent.instance.config.value("name") || framework_integration.application_name
    end

    def database_engine
      framework_integration.database_engine
    end

    def processors
      @processors ||= begin
                        proc_file = '/proc/cpuinfo'
                        processors = if !File.exist?(proc_file)
                                       1
                                     else
                                       lines = File.read("/proc/cpuinfo").lines.to_a
                                       lines.grep(/^processor\s*:/i).size
                                     end
                        [processors, 1].compact.max
                      end
    end

    def root
      return deploy_integration.root if deploy_integration
      framework_root
    end

    def framework_root
      if override_root = Agent.instance.config.value("application_root", true)
        return override_root
      end
      if framework == :rails
        RAILS_ROOT.to_s
      elsif framework == :rails3_or_4
        Rails.root
      elsif framework == :sinatra
        Sinatra::Application.root || "."
      else
        '.'
      end
    end

    def heroku?
      ENV['DYNO']
    end

    def hostname
      @hostname ||= heroku? ? ENV['DYNO'] : Socket.gethostname
    end


    # Returns the whole integration object
    # This needs to be improved. Frequently, multiple app servers gem are present and which
    # ever is checked first becomes the designated app server.
    #
    # Next step: (1) list out all detected app servers (2) install hooks for those that need it (passenger, rainbows, unicorn).
    def app_server_integration
      @app_server = SERVER_INTEGRATIONS.detect{ |integration| integration.present? }
    end

    # App server's name (symbol)
    def app_server
      app_server_integration.name
    end

    # If forking, don't start worker thread in the master process. Since it's
    # started as a Thread, it won't survive the fork.
    def forking?
      app_server_integration.forking?
    end

    def deploy_integration
      @deploy_integration ||= DEPLOY_INTEGRATIONS.detect{ |integration| integration.present? }
    end

    def deploy_integration?
      !@deploy_integration.nil?
    end

    ### ruby checks

    def rubinius?
      RUBY_VERSION =~ /rubinius/i
    end

    def jruby?
      defined?(JRuby)
    end

    def ruby_19?
      defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby" && RUBY_VERSION.match(/^1\.9/)
    end

    def ruby_187?
      defined?(RUBY_VERSION) && RUBY_VERSION.match(/^1\.8\.7/)
    end

    ### framework checks

    def sinatra?
      defined?(Sinatra::Application)
    end

  end # class Environemnt
end
