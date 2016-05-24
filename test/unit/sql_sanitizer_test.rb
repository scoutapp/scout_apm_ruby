require 'test_helper'

require 'scout_apm/utils/sql_sanitizer'

module ScoutApm
  module Utils
    class SqlSanitizerTest < Minitest::Test
      def setup
        ScoutApm::Agent.instance.init_logger
      end

      # Too long, and we just bail out to prevent long running instrumentation
      def test_long_sql
        sql = " " * 1001
        assert_equal '', SqlSanitizer.new(sql).to_s
      end

      def test_postgres_simple_select_of_first
        sql = %q|SELECT  "users".* FROM "users"  ORDER BY "users"."id" ASC LIMIT 1|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :postgres }
        assert_equal %q|SELECT "users".* FROM "users" ORDER BY "users"."id" ASC LIMIT 1|, ss.to_s
      end

      def test_postgres_where
        sql = %q|SELECT "users".* FROM "users" WHERE "users"."name" = $1  [["name", "chris"]]|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :postgres }
        assert_equal %q|SELECT "users".* FROM "users" WHERE "users"."name" = ?|, ss.to_s
      end

      def test_postgres_strips_literals
        # Strip strings
        sql = %q|SELECT "users".* FROM "users" INNER JOIN "blogs" ON "blogs"."user_id" = "users"."id" WHERE (blogs.title = 'hello world')|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :postgres }
        assert_equal %q|SELECT "users".* FROM "users" INNER JOIN "blogs" ON "blogs"."user_id" = "users"."id" WHERE (blogs.title = ?)|, ss.to_s

        # Strip integers
        sql = %q|SELECT "blogs".* FROM "blogs" WHERE (view_count > 10)|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :postgres }
        assert_equal %q|SELECT "blogs".* FROM "blogs" WHERE (view_count > ?)|, ss.to_s
      end

      def test_postgres_collapse_in_clause
        sql = %q|SELECT "blogs".* FROM "blogs" WHERE id IN (?, ?, ?)|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :postgres }
        assert_equal %q|SELECT "blogs".* FROM "blogs" WHERE id IN (?)|, ss.to_s
      end

      def test_postgres_collapse_in_clause_performacne
        sql = 'SELECT "users".* FROM "users" WHERE "users"."id" IN (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)'
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :postgres }

        assert_faster_than(0.01) do
          assert_equal %q|SELECT "users".* FROM "users" WHERE "users"."id" IN (?)|, ss.to_s
        end
      end

      def test_mysql_where
        sql = %q|SELECT `users`.* FROM `users` WHERE `users`.`name` = ?  [["name", "chris"]]|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT `users`.* FROM `users` WHERE `users`.`name` = ?|, ss.to_s
      end

      def test_mysql_limit
        sql = %q|SELECT  `blogs`.* FROM `blogs`  ORDER BY `blogs`.`id` ASC LIMIT 1|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT  `blogs`.* FROM `blogs`  ORDER BY `blogs`.`id` ASC LIMIT 1|, ss.to_s
      end

      def test_mysql_collpase_in_clause_performance
        sql = 'SELECT `users`.* FROM `users` WHERE `users`.`id` IN (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)'
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }

        assert_faster_than(0.01) do
          assert_equal %q|SELECT `users`.* FROM `users` WHERE `users`.`id` IN (?)|, ss.to_s
        end
      end

      def test_mysql_literals
        sql = %q|SELECT `blogs`.* FROM `blogs` WHERE (title = 'abc')|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT `blogs`.* FROM `blogs` WHERE (title = ?)|, ss.to_s

        sql = %q|SELECT `blogs`.* FROM `blogs` WHERE (title = "abc")|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT `blogs`.* FROM `blogs` WHERE (title = ?)|, ss.to_s
      end

      def test_mysql_quotes
        sql = %q|INSERT INTO `users` VALUES ('foo', 'b\'ar')|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|INSERT INTO `users` VALUES (?, ?)|, ss.to_s
      end

      def test_scrubs_invalid_encoding
        sql = "SELECT `blogs`.* FROM `blogs` WHERE (title = 'a\255c')".force_encoding('UTF-8')
        assert_equal false, sql.valid_encoding?
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT `blogs`.* FROM `blogs` WHERE (title = 'a_c')|, ss.sql
        assert_equal %q|SELECT `blogs`.* FROM `blogs` WHERE (title = ?)|, ss.to_s
      end

      def assert_faster_than(target_seconds)
        t1 = ::Time.now
        yield
        t2 = ::Time.now

        actual_time = t2.to_f - t1.to_f
        assert (actual_time < target_seconds), "Code took too long to execute, expected time: #{target_seconds}, actual time: #{actual_time}}"
      end
    end
  end
end
