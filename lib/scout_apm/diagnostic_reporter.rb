# Emits periodic memory diagnostic snapshots to stdout.
#
# Designed for Heroku deployments where stdout is the only reliable log
# destination. Snapshots fire every INTERVAL ticks of PeriodicWork (each tick
# is ~60 seconds), so the default of 5 means one snapshot every 5 minutes.
#
# Each snapshot writes two kinds of lines:
#   [Scout][Diag] key=value ...   — Scout-internal counters + GC/RSS summary
#   [Scout][Diag][Obj] N ClassName — top Ruby object counts from ObjectSpace
#
# The ObjectSpace scan pauses the world for ~50-200ms and is intentionally
# rate-limited to the snapshot interval to minimize production impact.
module ScoutApm
  class DiagnosticReporter
    INTERVAL = 5  # ticks between snapshots (each tick ≈ 60 s → 5 min cadence)
    TOP_CLASSES = 20

    def initialize(context)
      @context = context
      @tick = 0
    end

    def tick!
      @tick = (@tick + 1) % INTERVAL
      run if @tick == 0
    end

    private

    def run
      now = Time.now.utc.iso8601
      ctx = @context

      # --- Scout internal counters ---
      ttc_size   = ctx.transaction_time_consumed.send(:endpoints).size        rescue "?"
      hist_size  = ctx.request_histograms.send(:histograms).size              rescue "?"
      hbt_size   = ctx.request_histograms_by_time.size                        rescue "?"
      rp_size    = ctx.store.instance_variable_get(:@reporting_periods).size   rescue "?"

      # --- GC stats ---
      gc         = GC.stat
      live_slots = gc[:heap_live_slots]
      free_slots = gc[:heap_free_slots]
      alloc_obj  = gc[:total_allocated_objects]
      freed_obj  = gc[:total_freed_objects]
      gc_count   = gc[:count]

      # --- RSS (Linux / Heroku) ---
      rss_kb = begin
        File.read("/proc/self/status").match(/VmRSS:\s+(\d+)/)[1].to_i
      rescue
        nil
      end
      rss_str = rss_kb ? "#{(rss_kb / 1024.0).round(1)}mb" : "unavailable"

      $stdout.puts(
        "[Scout][Diag] ts=#{now} pid=#{$$} " \
        "rss=#{rss_str} " \
        "gc_live_slots=#{live_slots} gc_free_slots=#{free_slots} " \
        "gc_count=#{gc_count} gc_alloc=#{alloc_obj} gc_freed=#{freed_obj} " \
        "ttc_endpoints=#{ttc_size} request_histograms=#{hist_size} " \
        "histograms_by_time=#{hbt_size} reporting_periods=#{rp_size}"
      )

      # --- ObjectSpace scan ---
      # ObjectSpace.each_object(Object) skips BasicObject instances which
      # don't respond to #class and would otherwise raise NoMethodError.
      counts = Hash.new(0)
      ObjectSpace.each_object(Object) { |o| counts[o.class] += 1 }
      counts.sort_by { |_, v| -v }.first(TOP_CLASSES).each do |klass, count|
        $stdout.puts("[Scout][Diag][Obj] ts=#{now} pid=#{$$} count=#{count} class=#{klass}")
      end

      $stdout.flush
    rescue => e
      # Never let diagnostics crash the background worker
      $stdout.puts("[Scout][Diag] ts=#{now} pid=#{$$} error=#{e.class}: #{e.message}")
      $stdout.flush
    end
  end
end
