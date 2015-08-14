# Removes actual values from SQL. Used to both obfuscate the SQL and group
# similar queries in the UI.
module ScoutApm
  module Utils
    class SqlSanitizer
      attr_reader :sql
      attr_accessor :database_engine

      def initialize(sql)
        @sql = sql.dup
        @database_engine = ScoutApm::Environment.new.database_engine
      end

      def to_s
        return nil if sql.length > 1000 # safeguard - don't sanitize large SQL statements
        case database_engine
        when :postgres then to_s_postgres
        when :mysql    then to_s_mysql
        when :sqlite   then to_s_sqlite
        end
      end

      MULTIPLE_SPACES    = %r|\s+|.freeze
      MULTIPLE_QUESTIONS = /\?(,\?)+/.freeze
      TRAILING_SPACES    = /\s+$/.freeze

      PSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      PSQL_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      PSQL_REMOVE_INTEGERS = /(?<!LIMIT )\b\d+\b/.freeze
      PSQL_PLACEHOLDER = /\$\d+/.freeze

      def to_s_postgres
        sql.gsub!(PSQL_PLACEHOLDER, '?')
        sql.gsub!(PSQL_VAR_INTERPOLATION, '')
        sql.gsub!(PSQL_REMOVE_STRINGS, '?')
        sql.gsub!(PSQL_REMOVE_INTEGERS, '?')
        sql.gsub!(MULTIPLE_SPACES, ' ')
        sql.gsub!(TRAILING_SPACES, '')
        sql
      end

      MYSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      MYSQL_REMOVE_INTEGERS = /(?<!LIMIT )\b\d+\b/.freeze
      MYSQL_REMOVE_SINGLE_QUOTE_STRINGS = /'(?:[^']|'')*'/.freeze
      MYSQL_REMOVE_DOUBLE_QUOTE_STRINGS = /"(?:[^"]|"")*"/.freeze

      def to_s_mysql
        sql.gsub!(MYSQL_VAR_INTERPOLATION, '')
        sql.gsub!(MYSQL_REMOVE_SINGLE_QUOTE_STRINGS, '?')
        sql.gsub!(MYSQL_REMOVE_DOUBLE_QUOTE_STRINGS, '?')
        sql.gsub!(MYSQL_REMOVE_INTEGERS, '?')
        sql.gsub!(MULTIPLE_QUESTIONS, '?')
        sql.gsub!(TRAILING_SPACES, '')
        sql
      end

      SQLITE_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      SQLITE_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      SQLITE_REMOVE_INTEGERS = /(?<!LIMIT )\b\d+\b/.freeze

      def to_s_sqlite
        sql.gsub!(SQLITE_VAR_INTERPOLATION, '')
        sql.gsub!(SQLITE_REMOVE_STRINGS, '?')
        sql.gsub!(SQLITE_REMOVE_INTEGERS, '?')
        sql.gsub!(MULTIPLE_SPACES, ' ')
        sql.gsub!(TRAILING_SPACES, '')
      end
    end
  end
end
