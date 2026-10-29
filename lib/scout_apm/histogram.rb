module ScoutApm
  HistogramBin = Struct.new(:value, :count)

  class NumericHistogram
    # This class should be threadsafe.
    attr_reader :mutex

    attr_reader :max_bins
    attr_reader :bins
    attr_accessor :total

    def marshal_dump
      [@max_bins, @bins, @total]
    end

    def marshal_load(array)
      @max_bins, @bins, @total = array
      @mutex = Mutex.new
    end

    def initialize(max_bins)
      @max_bins = max_bins
      @bins = []
      @total = 0
      @mutex = Mutex.new
    end

    def add(new_value)
      mutex.synchronize do
        @total += 1
        create_new_bin(new_value.to_f)
        trim
      end
    end

    def quantile(q)
      mutex.synchronize do
        return 0 if total == 0

        if q > 1
          q = q / 100.0
        end

        count = q.to_f * total.to_f

        bins.each_with_index do |bin, index|
          count -= bin.count

          if count <= 0
            return bin.value
          end
        end

        # If we fell through, we were asking for the last (max) value
        return bins[-1].value
      end
    end

    # Given a value, where in this histogram does it fall?
    # Returns a float between 0 and 1
    def approximate_quantile_of_value(v)
      mutex.synchronize do
        return 100 if total == 0

        count_examined = 0

        bins.each_with_index do |bin, index|
          if v <= bin.value
            break
          end

          count_examined += bin.count
        end

        count_examined / total.to_f
      end
    end

    def mean
      mutex.synchronize do
        if total == 0
          return 0
        end

        sum = bins.inject(0) { |s, bin| s + (bin.value * bin.count) }
        return sum.to_f / total.to_f
      end
    end

    def combine!(other)
      mutex.synchronize do
        other.mutex.synchronize do
          @bins = merge_bins(other.bins + @bins)
          @total += other.total
          trim
          self
        end
      end
    end

    def as_json
      mutex.synchronize do
        bins.map{ |b|
          [
            ScoutApm::Utils::Numbers.round(b.value, 4),
            b.count
          ]
        }
      end
    end

    private

    # If we exactly match an existing bin, add to it, otherwise create a new bin holding a count for the new value.
    def create_new_bin(new_value)
      bins.each_with_index do |bin, index|
        # If it matches exactly, increment the bin's count
        if bin.value == new_value
          bin.count += 1
          return
        end

        # We've gone one bin too far, so insert before the current bin.
        if bin.value > new_value
          # Insert at this index
          new_bin = HistogramBin.new(new_value, 1)
          bins.insert(index, new_bin)
          return
        end
      end

      # If we get to here, the bin needs to be added to the end.
      bins << HistogramBin.new(new_value, 1)
    end

    def merge_bins(bins)
      merged = []
      bins.sort_by(&:value).each do |bin|
        last = merged.last
        if last && last.value == bin.value
          last.count += bin.count
        else
          merged << HistogramBin.new(bin.value, bin.count)
        end
      end
      merged
    end

    def trim
      return if bins.length <= max_bins

      deltas = Array.new(bins.length - 1) { |i| bins[i + 1].value - bins[i].value }
      while bins.length > max_bins
        index = deltas.index(deltas.min)
        left = bins[index]
        right = bins[index + 1]
        count = left.count + right.count
        bins[index, 2] = HistogramBin.new((left.value * left.count + right.value * right.count) / count, count)

        deltas.delete_at(index)
        deltas[index - 1] = bins[index].value - bins[index - 1].value if index > 0
        deltas[index] = bins[index + 1].value - bins[index].value if index < bins.length - 1
      end
    rescue => e
      ScoutApm::Agent.instance.context.logger.info("Error in NumericHistogram#trim. #{e.message}, #{e.backtrace}, #{self.inspect}")
      raise
    end
  end
end
