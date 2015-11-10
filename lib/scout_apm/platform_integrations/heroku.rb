module ScoutApm
  module PlatformIntegrations
    class Heroku
      def present?
        !! ENV['DYNO']
      end

      def name
        "Heroku"
      end

      def hostname
        ENV['DYNO']
      end
    end
  end
end
