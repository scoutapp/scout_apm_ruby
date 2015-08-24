module ScoutApm
  module ServerIntegrations
    class Thin
      def name
        :thin
      end

      def forking?; false; end

      def present?
        if defined?(::Thin) && defined?(::Thin::Server)
          # Ensure Thin is actually initialized. It could just be required and not running.
          ObjectSpace.each_object(::Thin::Server) { |x| return true }
          false
        end
      end

      # TODO: What does it mean to install on a non-forking env?
      def install
      end
    end
  end
end
