require 'scout_apm/environment'

# Removes actual values from SQL. Used to both obfuscate the SQL and group
# similar queries in the UI.
module ScoutApm
  module Utils
    class BacktraceParser

      def initialize(call_stack)
        @call_stack = call_stack
        # We can't use a constant as it'd be too early to fetch environment info
        @@app_dir_regex ||= /\A(#{ScoutApm::Environment.instance.root.to_s.gsub('/','\/')}\/)(app\/(.+))/.freeze
      end

      # Given a call stack Array, grabs the first call within the application root directory.
      def call
        # We used to return an array of up to 5 elements...this will return a single element-array for backwards compatibility.
        # Only the first element is used in Github code display.
        stack = []
        @call_stack.each_with_index do |c,i|
          # TODO - don't gsub every time ... store it.
          if m = c.match(@@app_dir_regex)
            stack << m[2]
            break
          end
        end
        stack
      end

    end
  end
end