module ScoutApm
  class StatsdReporter
    attr_reader :underlying

    def initialize(underlying_statsd)
      @underlying = underlying_statsd
      # @context ?
    end

    def increment(*args)
      stat = args.first
      val = ScoutApm::Context.get(stat).to_f
      ScoutApm::Context.add({stat => val + 1})
      relay(:increment, args)
    end

    def decrement(*args)
      stat = args.first
      val = ScoutApm::Context.get(stat).to_f
      ScoutApm::Context.add({stat => val - 1})
      relay(:decrement, args)
    end

    def count(*args)
      stat = args.first
      val = ScoutApm::Context.get(stat).to_f
      ScoutApm::Context.add({stat => val + args[1]})
      relay(:count, args)
    end

    def timing(*args)
      stat = args.first
      val = ScoutApm::Context.get(stat).to_f
      ScoutApm::Context.add({stat => val + args[1]})
      relay(:timing, args)
    end

    def time(*args, &block)
      stat = args.first
      start = Time.now
      res = underlying.send(:time, *args, &block)
      ScoutApm::Context.add({stat => (Time.now - start)*1000})
      res
    end

    def method_missing(m, *args, &block)
      if args && args.any? && block
        underlying.send(m.to_sym, *args, &block)
      elsif args.any?
        underlying.send(m.to_sym, *args)
      else
        underlying.send(m.to_sym)
      end
    end

    def relay(operation, args)
      underlying.send(operation, *args)
    end
  end
end