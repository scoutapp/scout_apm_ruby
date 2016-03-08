module ScoutApm
  module Serializers
    module PayloadSerializerToJson
      class << self
        def serialize(metadata, metrics, slow_transactions, jobs)
          metadata.merge!({:payload_version => 2})

          jsonify_hash({:metadata => metadata,
                        :metrics => rearrange_the_metrics(metrics),
                        :slow_transactions => rearrange_the_slow_transactions(slow_transactions),
                        :jobs => JobsSerializerToJson.new(jobs).as_json,
                      })
        end

        # Old style of metric serializing.
        def rearrange_the_metrics(metrics)
          metrics.to_a.map do |meta, stats|
            stats.as_json.merge(:key => meta.as_json)
          end
        end

        def rearrange_the_slow_transactions(slow_transactions)
          slow_transactions.to_a.map do |slow_t|
            slow_t.as_json.merge(:metrics => rearrange_the_metrics(slow_t.metrics))
          end
        end

        def jsonify_hash(hash)
          str_parts = []
          hash.each do |key, value|
            formatted_key = format_by_type(key)
            formatted_value = format_by_type(value)
            str_parts << "#{formatted_key}:#{formatted_value}"
          end
          "{#{str_parts.join(",")}}"
        end

        ESCAPE_MAPPINGS = {
          "\b" => '\\b',
          "\t" => '\\t',
          "\n" => '\\n',
          "\f" => '\\f',
          "\r" => '\\r',
          '"'  => '\\"',
          '\\' => '\\\\',
        }

        def escape(string)
          ESCAPE_MAPPINGS.inject(string.to_s) {|s, (bad, good)| s.gsub(bad, good) }
        end

        def format_by_type(formatee)
          case formatee
          when Hash
            jsonify_hash(formatee)
          when Array
            all_the_elements = formatee.map {|value_guy| format_by_type(value_guy)}
            "[#{all_the_elements.join(",")}]"
          when Numeric
            formatee
          when nil
            "null"
          else # strings and everything
            %Q["#{escape(formatee)}"]
          end
        end
      end
    end
  end
end
