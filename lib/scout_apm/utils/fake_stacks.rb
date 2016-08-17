# A fake implementation of the allocations native extension, for systems that don't support it.
module ScoutApm
  module Instruments
    class Stacks
      ENABLED = false

      class << self
        def install(*args)
          # noop
        end

        def uninstall(*args)
          # noop
        end

        def start(*args)
          # noop
        end

        def add_profiled_thread(*args)
          # noop
        end

        def remove_profiled_thread(*args)
          # noop
        end

        def profile_frames(*args)
          [] # frames that were profiled (none)
        end

        def start_sampling(*args)
          # noop
        end

        def stop_sampling(*args)
          # noop
        end

        def update_indexes(*args)
          # noop
          true
        end

        def current_trace_index(*args)
          :opaque_value
        end

        def current_frame_index(*args)
          :opaque_value
        end

        def frame_klass(*args)
          nil
        end

        def frame_method(*args)
          nil
        end

        def frame_file(*args)
          nil
        end

        def frame_lineno(*args)
          nil
        end

        def skipped_in_gc(*args)
          0
        end

        def skipped_in_handler(*args)
          0
        end

        def skipped_in_job_registered(*args)
          0
        end

        def skipped_in_not_running(*args)
          0
        end
      end
    end
  end
end
