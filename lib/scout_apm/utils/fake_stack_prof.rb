# A fake implementation of stackprof, for systems that don't support it.
class StackProf
  def self.start(*args)
    @running = true
  end

  def self.stop(*args)
    @running = false
  end

  def running?
    !!@running
  end

  def run(*args)
    start
    yield
    stop
    results
  end

  def sample(*args)
  end

  def results(*args)
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
end
