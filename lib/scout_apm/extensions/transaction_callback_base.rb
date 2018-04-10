module ScoutApm
  module Extensions
    # This is the Base class that Transaction Callback Extensions should inherit from.
    # This is called via +TrackedRequest#record!+ and is used by both web and background job transactions.
    class TransactionCallbackBase

      def logger
        ScoutApm::Agent.instance.context.logger
      end

    end
  end
end