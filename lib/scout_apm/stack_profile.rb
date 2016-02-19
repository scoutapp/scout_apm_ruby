require 'stack_profile'

class StackProfile
  def self.hello
    puts "hello"
  end
end

ScoutApm.after_gc_start_hook = proc { p StackProfile.getstack }

