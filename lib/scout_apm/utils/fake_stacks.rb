# A fake implementation of the allocations native extension, for systems that don't support it.
module ScoutApm
  module Instruments
    class Stacks
      ENABLED = false
    end
  end
end
