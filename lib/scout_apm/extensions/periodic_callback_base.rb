module ScoutApm
  module Extensions
    # This is the Base class that Periodic Callback Extensions should inherit from.
    # This is called via +#report_to_server#+, which is called once per-minute. 
    # These execute in a background thread so external HTTP calls are OK.
    class PeriodicCallbackBase

      attr_reader :reporting_period
      attr_reader :metadata

      def initialize(reporting_period, metadata)
        @reporting_period = reporting_period
        @metadata = metadata
      end
    end
  end
end