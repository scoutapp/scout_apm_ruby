# A lack of app server to integrate with.
# Null Object pattern

module ScoutApm
  module ServerIntegrations
    class Null
      def name
        :null
      end

      def present?
        true
      end

      def install
        # Nothing to do.
      end

      def forking?
        false
      end
    end
  end
end
