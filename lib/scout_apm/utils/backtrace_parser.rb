require 'scout_apm/environment'

# Removes actual values from SQL. Used to both obfuscate the SQL and group
# similar queries in the UI.
module ScoutApm
  module Utils
    class BacktraceParser

      APP_FRAMES = 3 # will return up to 3 frames from the app stack.

      def initialize(call_stack)
        @call_stack = call_stack
        # We can't use a constant as it'd be too early to fetch environment info
        @@app_dir_regex ||= /\A(#{ScoutApm::Environment.instance.root.to_s.gsub('/','\/')}\/)(app\/(.+))/.freeze
      end

      # Given a call stack Array, grabs the first +APP_FRAMES+ callers within the application root directory.
      def call
        stack = []
        @call_stack.each_with_index do |c,i|
          if m = c.match(@@app_dir_regex)
            stack << m[2]
            break if stack.size == APP_FRAMES
          end
        end
        stack
      end

    end
  end
end