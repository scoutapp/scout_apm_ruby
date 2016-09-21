module ScoutApm
  module Instruments
    module Process
      class ProcessMemory
        attr_reader :logger

        # Account for Darwin returning maxrss in bytes and Linux in KB. Used by the slow converters. Doesn't feel like this should go here though...more of a utility.
        def self.rss_to_mb(rss)
          rss.to_f/1024/(ScoutApm::Agent.instance.environment.os == 'darwin' ? 1024 : 1)
        end

        def self.rss
          ::Process.rusage.maxrss
        end

        def self.rss_in_mb
          rss_to_mb(rss)
        end

        def initialize(logger)
          @logger = logger
        end

        def metric_type
          "Memory"
        end

        def metric_name
          "Physical"
        end

        def human_name
          "Process Memory"
        end

        def metrics(timestamp, store)
          result = run
          if result
            meta = MetricMeta.new("#{metric_type}/#{metric_name}")
            stat = MetricStats.new(false)
            stat.update!(result)
            store.track!({ meta => stat }, :timestamp => timestamp)
          else
            {}
          end
        end

        def run
          self.class.rss_in_mb.tap { |res| logger.debug "#{human_name}: #{res.inspect}" }
        end
      end
    end
  end
end
