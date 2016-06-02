$: << "./lib"

require 'scout_apm'
require 'stacks'

class OneTrace
  attr_reader :data
  attr_reader :num

  def initialize(num)
    puts "Initialized, expecting #{num}"
    @num = num
    @data = []
  end

  def add(file, line, label, klass)
    @data << [file, line, label, klass]
  end
end

class GlobalVar
  def self.collect(trace)
    puts "***************************************************************"

    puts "Collected some data in ruby:\n#{trace.data.map{|x| "#{x[0]}:#{x[1]}\t#{x[3]}##{x[2]}" }.join("\n")}"
  end
end

####################################
#
def quux
  while true
    puts "Hello"
    sleep 0.5
  end
end

class Whipple
  def baz
    quux
  end
end

def bar
  w = Whipple.new
  w.baz
end

def foo
  bar
end

foo
