require 'singleton'

# Used to retrieve environment information for this application.
module ScoutApm
  class Environment
    include Singleton

    # I've put Thin and Webrick last as they are often used in development and included in Gemfiles
    # but less likely used in production.
    SERVER_INTEGRATIONS = [
      ScoutApm::ServerIntegrations::Passenger.new(Logger.new(STDOUT)),
      ScoutApm::ServerIntegrations::Unicorn.new(Logger.new(STDOUT)),
      ScoutApm::ServerIntegrations::Rainbows.new(Logger.new(STDOUT)),
      ScoutApm::ServerIntegrations::Puma.new(Logger.new(STDOUT)),
      ScoutApm::ServerIntegrations::Thin.new(Logger.new(STDOUT)),
      ScoutApm::ServerIntegrations::Webrick.new(Logger.new(STDOUT)),
      ScoutApm::ServerIntegrations::Null.new(Logger.new(STDOUT)), # must be last
    ]

    FRAMEWORK_INTEGRATIONS = [
      ScoutApm::FrameworkIntegrations::Rails2.new,
      ScoutApm::FrameworkIntegrations::Rails3Or4.new,
      ScoutApm::FrameworkIntegrations::Sinatra.new,
      ScoutApm::FrameworkIntegrations::Ruby.new, # Fallback if none match
    ]

    def env
      @env ||= framework_integration.env
    end

    def framework
      framework_integration.name
    end

    def framework_integration
      @framework ||= FRAMEWORK_INTEGRATIONS.detect{ |integration| integration.present? }
    end

    def database_engine
      default = :mysql

      if defined?(ActiveRecord::Base)
        return default unless ActiveRecord::Base.connected?

        case ActiveRecord::Base.connection.class.to_s
        when "ActiveRecord::ConnectionAdapters::MysqlAdapter"
          :mysql
        when "ActiveRecord::ConnectionAdapters::PostgreSQLAdapter"
          :postgres
        when "ActiveRecord::ConnectionAdapters::SQLite3Adapter"
          :sqlite
        else
          default
        end
      else
        # TODO: detection outside of Rails
        default
      end
    end

    def processors
      @processors ||= begin
                        proc_file = '/proc/cpuinfo'
                        if !File.exist?(proc_file)
                          processors = 1
                        elsif `cat #{proc_file} | grep 'model name' | wc -l` =~ /(\d+)/
                          processors = $1.to_i
                        end

                        [processors, 1].max
                      end
    end

    def root
      if framework == :rails
        RAILS_ROOT.to_s
      elsif framework == :rails3_or_4
        Rails.root
      elsif framework == :sinatra
        Sinatra::Application.root
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
