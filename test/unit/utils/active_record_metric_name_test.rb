require 'test_helper'
require 'scout_apm/utils/active_record_metric_name'

class ActiveRecordMetricNameTest < Minitest::Test
  # This is a bug report from Андрей Филиппов <tmn.sun@gmail.com>
  # The code that triggered the bug was: ActiveRecord::Base.connection.execute("%some sql%", :skip_logging)
  def test_symbol_name
    sql = "SELECT * FROM users /*application:Testapp,controller:public,action:index*/"
    name = :skip_logging

    mn = ScoutApm::Utils::ActiveRecordMetricName.new(sql, name)
    assert_equal "SQL/Unknown", mn.to_s
  end

  def test_postgres_column_lookup
    sql = <<-EOF
    SELECT t.oid, t.typname, t.typelem, t.typdelim, t.typinput, r.rngsubtype, t.typtype, t.typbasetype
                  FROM pg_type as t
                  LEFT JOIN pg_range as r ON oid = rngtypid
                  WHERE
                    t.typname IN ('int2', 'int4', 'int8', 'oid', 'float4', 'float8', 'text', 'varchar', 'char', 'name', 'bpchar', 'bool', 'bit', 'varbit', 'timestamptz', 'date', 'time', 'money', 'bytea', 'point', 'hstore', 'json', 'jsonb', 'cidr', 'inet', 'uuid', 'xml', 'tsvector', 'macaddr', 'citext', 'ltree', 'interval', 'path', 'line', 'polygon', 'circle', 'lseg', 'box', 'timestamp', 'numeric')
                    OR t.typtype IN ('r', 'e', 'd')
                    OR t.typinput::varchar = 'array_in'
                    OR t.typelem != 0
    EOF

    name = "SCHEMA"

    mn = ScoutApm::Utils::ActiveRecordMetricName.new(sql, name)
    assert_equal "SQL/Unknown", mn.to_s
  end


  def test_user_find
    sql = %q|SELECT "users".* FROM "users" /*application:Testapp,controller:public,action:index*/|
    name = "User Load"

    mn = ScoutApm::Utils::ActiveRecordMetricName.new(sql, name)
    assert_equal "User/find", mn.to_s
  end

  def test_without_name
    sql = %q|SELECT "users".* FROM "users" /*application:Testapp,controller:public,action:index*/|
    name = nil

    mn = ScoutApm::Utils::ActiveRecordMetricName.new(sql, name)
    assert_equal "SQL/Unknown", mn.to_s
  end

  def test_with_sql_name
    sql = %q|INSERT INTO "users".* VALUES (1,2,3)|
    name = "SQL"

    mn = ScoutApm::Utils::ActiveRecordMetricName.new(sql, name)
    assert_equal "SQL/Unknown", mn.to_s
  end

  # TODO: Determine if there should be a distinction between Unknown and Other.
  def test_with_custom_name
    sql = %q|SELECT "users".* FROM "users" /*application:Testapp,controller:public,action:index*/|
    name = "A whole sentance describing what's what"

    mn = ScoutApm::Utils::ActiveRecordMetricName.new(sql, name)
    assert_equal "SQL/other", mn.to_s
  end
end
