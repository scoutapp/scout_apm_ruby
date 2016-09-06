module ScoutApm
  class GitRevision

    attr_accessor :sha

    def initialize
      @sha = detect
      ScoutApm::Agent.instance.logger.debug "Detected Git Revision [#{@sha}]"
    end

    private

    def detect
      detect_from_env_var    ||
      detect_from_heroku     ||
      detect_from_capistrano ||
      detect_from_git
    end

    def detect_from_heroku
      ENV['HEROKU_SLUG_COMMIT']
    end

    def detect_from_env_var
      ENV['SCOUT_REVISION_SHA']
    end

    def detect_from_capistrano
      version = File.read(File.join(app_root, 'REVISION')).strip
      # Capistrano 3.0 - 3.1.x
      version || File.open(File.join(app_root, '..', 'revisions.log')).to_a.last.strip.sub(/.*as release ([0-9]+).*/, '\1')
    rescue
      ScoutApm::Agent.instance.logger.debug "Unable to detect Git Revision from Capistrano: #{$!.message}"
      nil
    end

    def detect_from_git
      if File.directory?(".git")
        `git rev-parse --short HEAD`.strip 
      end
    rescue
      ScoutApm::Agent.instance.logger.debug "Unable to detect Git Revision from Git: #{$!.message}"
      nil
    end

    def app_root
      ScoutApm::Environment.instance.root
    end

  end
end