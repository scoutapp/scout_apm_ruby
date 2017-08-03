require 'scout_apm/environment'

# Given a call stack Array, grabs the first +APP_FRAMES+ callers within the
# application root directory.
#
module ScoutApm
  module Utils
    class BacktraceParser
      # will return this many backtrace frames from the app stack.
      APP_FRAMES = 8

      attr_reader :call_stack

      def initialize(call_stack, root=ScoutApm::Environment.instance.root)
        @call_stack = call_stack
        # We can't use a constant as it'd be too early to fetch environment info
        #
        # This regex looks for files under the app root, inside lib/, app/, and
        # config/ dirs, and captures the path under root.
        @@app_dir_regex = %r[#{root}/((?:lib/|app/|config/).*)]
      end

      def call
        stack = []
        call_stack.each do |c|
          if m = c.match(@@app_dir_regex)
            stack << ScoutApm::Utils::Scm.relative_scm_path(m[1])
            break if stack.size == APP_FRAMES
          end
        end
        stack
      end
    end
  end
end
