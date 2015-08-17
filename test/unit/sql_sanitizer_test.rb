require 'test_helper'

require 'scout_apm/utils/sql_sanitizer'

module ScoutApm
  module Utils
    class SqlSanitizerTest < Minitest::Test
      # Too long, and we just bail out to prevent long running instrumentation
      def test_long_sql
        sql = " " * 1001
        assert_nil SqlSanitizer.new(sql).to_s
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

      def test_mysql_literals
        sql = %q|SELECT `blogs`.* FROM `blogs` WHERE (title = 'abc')|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT `blogs`.* FROM `blogs` WHERE (title = ?)|, ss.to_s

        sql = %q|SELECT `blogs`.* FROM `blogs` WHERE (title = "abc")|
        ss = SqlSanitizer.new(sql).tap{ |it| it.database_engine = :mysql }
        assert_equal %q|SELECT `blogs`.* FROM `blogs` WHERE (title = ?)|, ss.to_s
      end
    end
  end
end
