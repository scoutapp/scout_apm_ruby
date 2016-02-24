require 'test_helper'
require 'scout_apm/attribute_arranger'
require 'scout_apm/bucket_name_splitter'
require 'scout_apm/serializers/payload_serializer'
require 'scout_apm/serializers/payload_serializer_to_json'
require 'scout_apm/slow_transaction'
require 'scout_apm/metric_meta'
require 'scout_apm/metric_stats'
require 'scout_apm/stackprof_tree_collapser'
require 'scout_apm/utils/fake_stack_prof'
require 'scout_apm/context'
require 'ostruct'
require 'json' # to deserialize what has been manually serialized by the production code

# stub the report_format value
# class ScoutApm::Agent
  # module Config
    # def self.value(key)
      # 'json'
    # end
  # end

  # def self.instance
    # OpenStruct.new(:config => Config)
  # end
# end

class PayloadSerializerTest < Minitest::Test

  def test_serializes_metadata_as_json
    metadata = {
      :app_root => "/srv/app/rootz",
      :unique_id => "unique_idz",
      :agent_version => 123
    }
    payload = ScoutApm::Serializers::PayloadSerializerToJson.serialize(metadata, {}, {})

    # symbol keys turn to strings
    formatted_metadata = {
      "app_root" => "/srv/app/rootz",
      "unique_id" => "unique_idz",
      "agent_version" => 123,
      "payload_version" => 2
    }
    assert_equal formatted_metadata, JSON.parse(payload)["metadata"]
  end

  def test_serializes_metrics_as_json
    metrics = {
      ScoutApm::MetricMeta.new('ActiveRecord/all').tap { |meta|
        meta.desc = "SELECT * from users where filter=?"
        meta.extra = {:user => 'cooluser'}
        meta.metric_id = nil
        meta.scope = "Controller/apps/checkin"
      } => ScoutApm::MetricStats.new.tap { |stats|
        stats.call_count = 16
        stats.max_call_time = 0.005338062
        stats.min_call_time = 0.000613518
        stats.sum_of_squares = 9.8040860751126e-05
        stats.total_call_time = 0.033245704
        stats.total_exclusive_time = 0.033245704
      },
      ScoutApm::MetricMeta.new("Controller/apps/checkin").tap { |meta|
        meta.desc = nil
        meta.extra = {}
        meta.metric_id = nil
        meta.scope = nil
      } => ScoutApm::MetricStats.new.tap { |stats|
        stats.call_count = 2
        stats.max_call_time = 0.078521419
        stats.min_call_time = 0.034881757
        stats.sum_of_squares = 0.007382350213180609
        stats.total_call_time = 0.113403176
        stats.total_exclusive_time = 0.07813208899999999
      }
    }
    payload = ScoutApm::Serializers::PayloadSerializerToJson.serialize({}, metrics, {})
    formatted_metrics = [
      {
        "key" => {
          "bucket" => "ActiveRecord",
          "name" => "all",
          "desc" => "SELECT * from users where filter=?",
          "extra" => {
            "user" => "cooluser",
          },
          "scope" => {
            "bucket" => "Controller",
            "name" => "apps/checkin",
          },
        },
        "call_count" => 16,
        "max_call_time" => 0.005338062,
        "min_call_time" => 0.000613518,
        "total_call_time" => 0.033245704,
        "total_exclusive_time" => 0.033245704,
      },
      {
        "key" => {
          "bucket" => "Controller",
          "name" => "apps/checkin",
          "desc" => nil,
          "extra" => {},
          "scope" => nil,
        },
        "call_count" => 2,
        "max_call_time" => 0.078521419,
        "min_call_time" => 0.034881757,
        "total_call_time" => 0.113403176,
        "total_exclusive_time" => 0.07813208899999999,
      }
    ]
    assert_equal formatted_metrics, JSON.parse(payload)["metrics"]
  end

  def test_serializes_slow_transactions_as_json
    slow_transaction_metrics = {
      ScoutApm::MetricMeta.new('ActiveRecord/all').tap { |meta|
        meta.desc = "SELECT *\nfrom users where filter=?"
        meta.extra = {:user => 'cooluser'}
        meta.metric_id = nil
        meta.scope = "Controller/apps/checkin"
      } => ScoutApm::MetricStats.new.tap { |stats|
        stats.call_count = 16
        stats.max_call_time = 0.005338062
        stats.min_call_time = 0.000613518
        stats.sum_of_squares = 9.8040860751126e-05
        stats.total_call_time = 0.033245704
        stats.total_exclusive_time = 0.033245704
      },
      ScoutApm::MetricMeta.new("Controller/apps/checkin").tap { |meta|
        meta.desc = nil
        meta.extra = {}
        meta.metric_id = nil
        meta.scope = nil
      } => ScoutApm::MetricStats.new.tap { |stats|
        stats.call_count = 2
        stats.max_call_time = 0.078521419
        stats.min_call_time = 0.034881757
        stats.sum_of_squares = 0.007382350213180609
        stats.total_call_time = 0.113403176
        stats.total_exclusive_time = 0.07813208899999999
      }
    }
    context = ScoutApm::Context.new
    context.add({"this" => "that"})
    context.add_user({"hello" => "goodbye"})
    slow_t = ScoutApm::SlowTransaction.new("http://example.com/blabla", "Buckethead/something/else", 1.23, slow_transaction_metrics, context, Time.at(1448198788), StackProf.new)
    payload = ScoutApm::Serializers::PayloadSerializerToJson.serialize({}, {}, [slow_t])
    formatted_slow_transactions = [
      {
        "key" => {
          "bucket" => "Buckethead",
          "name" => "something/else"
        },
        "time" => "2015-11-22 06:26:28 -0700",
        "total_call_time" => 1.23,
        "uri" => "http://example.com/blabla",
        "context" => {"this"=>"that", "user"=>{"hello"=>"goodbye"}},
        "prof" => [],
        "metrics" => [
          {
            "key" => {
              "bucket" => "ActiveRecord",
              "name" => "all",
              "desc" => "SELECT *\nfrom users where filter=?",
              "extra" => {
                "user" => "cooluser",
              },
              "scope" => {
                "bucket" => "Controller",
                "name" => "apps/checkin",
              },
            },
            "call_count" => 16,
            "max_call_time" => 0.005338062,
            "min_call_time" => 0.000613518,
            "total_call_time" => 0.033245704,
            "total_exclusive_time" => 0.033245704,
          },
          {
            "key" => {
              "bucket" => "Controller",
              "name" => "apps/checkin",
              "desc" => nil,
              "extra" => {},
              "scope" => nil,
            },
            "call_count" => 2,
            "max_call_time" => 0.078521419,
            "min_call_time" => 0.034881757,
            "total_call_time" => 0.113403176,
            "total_exclusive_time" => 0.07813208899999999,
          }
        ]
      }
    ]

    assert_equal formatted_slow_transactions, JSON.parse(payload)["slow_transactions"]
  end

  def test_escapes_json_quotes
    metadata = {
      :quotie => "here are some \"quotes\"",
      :payload_version => 2,
    }
    payload = ScoutApm::Serializers::PayloadSerializerToJson.serialize(metadata, {}, {})

    # symbol keys turn to strings
    formatted_metadata = {
      "quotie" => "here are some \"quotes\"",
      "payload_version" => 2
    }
    assert_equal formatted_metadata, JSON.parse(payload)["metadata"]
  end

  def test_escapes_newlines
    json = { "foo" => "\bbar\nbaz\r" }
    assert_equal json, JSON.parse(ScoutApm::Serializers::PayloadSerializerToJson.jsonify_hash(json))
  end
end
