module ScoutApm
  module ServerIntegrations
    class Webrick
      def name
        :webrick
      end

      def forking?; false; end

      def present?
        defined?(::WEBrick) && defined?(::WEBrick::VERSION)
      end

      # TODO: What does it mean to install on a non-forking env?
      def install
      end
    end
  end
end
