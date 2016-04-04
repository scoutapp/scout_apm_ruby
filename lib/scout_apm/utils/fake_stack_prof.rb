# A fake implementation of stackprof, for systems that don't support it.
module StackProf
  def self.start(*args)
    @running = true
  end

  def self.stop(*args)
    @running = false
  end

  def self.running?
    !!@running
  end

  def self.run(*args)
    start
    yield
    stop
    results
  end

  def self.sample(*args)
  end

  def self.results(*args)
    {
      :version => 0.0,
      :mode => :wall,
      :interval => 1000,
      :samples => 0,
      :gc_samples => 0,
      :missed_samples => 0,
      :frames => {},
    }
  end

  def self.fake?
    true
  end
end
