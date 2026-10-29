require 'json'

module ScoutApm
  module Serializers
    module PayloadSerializerToJson
      class << self
        def serialize(metadata, metrics, slow_transactions, jobs, slow_jobs, histograms, db_query_metrics, external_service_metrics, traces)
          metadata.merge!({:payload_version => 2})

          jsonify_hash({:metadata => metadata,
                        :metrics => rearrange_the_metrics(metrics),
                        :slow_transactions => rearrange_the_slow_transactions(slow_transactions),
                        :jobs => JobsSerializerToJson.new(jobs).as_json,
                        :slow_jobs => SlowJobsSerializerToJson.new(slow_jobs).as_json,
                        :histograms => HistogramsSerializerToJson.new(histograms).as_json,
                        :db_metrics => {
                          :query => DbQuerySerializerToJson.new(db_query_metrics).as_json,
                        },
                        :es_metrics => {
                          :http => ExternalServiceSerializerToJson.new(external_service_metrics).as_json,
                        },
                        :span_traces => traces.map{ |t| t.as_json },
          })
        end

        # For the old style of metric serializing.
        def rearrange_the_metrics(metrics)
          metrics.to_a.map do |meta, stats|
            stats.as_json.merge(:key => meta.as_json)
          end
        end

        # takes an array of slow transactions
        def rearrange_the_slow_transactions(slow_transactions)
          slow_transactions.to_a.map { |t| rearrange_slow_transaction(t) }
        end

        # takes just one slow transaction
        def rearrange_slow_transaction(slow_t)
          slow_t.as_json.merge(:metrics => rearrange_the_metrics(slow_t.metrics), :allocation_metrics => rearrange_the_metrics(slow_t.allocation_metrics))
        end

        def jsonify_hash(hash)
          JSON.generate(json_ready(hash), :allow_nan => true, :max_nesting => false)
        end

        def json_ready(value)
          case value
          when Hash
            value.each_with_object({}) { |(key, item), ready| ready[json_ready(key)] = json_ready(item) }
          when Array
            value.map { |item| json_ready(item) }
          when Integer, Float, nil
            value
          when Numeric
            value.to_f
          when Time
            value.iso8601
          else
            valid_utf8(value.to_s)
          end
        end

        def valid_utf8(string)
          return string if string.valid_encoding? && string.encoding != Encoding::BINARY

          string = string.dup.force_encoding(Encoding::UTF_8)
          string.valid_encoding? ? string : string.scrub
        end
      end
    end
  end
end
