
module ScoutApm
  module Utils
    module SqlRegex
      MULTIPLE_SPACES    = %r|\s+|.freeze
      MULTIPLE_QUESTIONS = /\?(,\?)+/.freeze

      PSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      PSQL_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      PSQL_REMOVE_INTEGERS = /\b\d+\b/.freeze
      PSQL_PLACEHOLDER = /\$\d+/.freeze
      PSQL_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze
      PSQL_AFTER_WHERE = /(?:WHERE\s+).*?(?:SELECT|$)/i.freeze
      PSQL_AFTER_SET = /(?:SET\s+).*?(?:WHERE|$)/i.freeze

      MYSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      MYSQL_REMOVE_INTEGERS = /\b\d+\b/.freeze
      MYSQL_REMOVE_SINGLE_QUOTE_STRINGS = /'(?:\\'|[^']|'')*'/.freeze
      MYSQL_REMOVE_DOUBLE_QUOTE_STRINGS = /"(?:\\"|[^"]|"")*"/.freeze
      MYSQL_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze

      SQLITE_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      SQLITE_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      SQLITE_REMOVE_INTEGERS = /\b\d+\b/.freeze

      # This is not officially supported, but will do its best.
      SQLSERVER_EXECUTESQL = /EXEC sp_executesql N'(.*?)'.*/
      SQLSERVER_REMOVE_INTEGERS = /\b\d+\b/.freeze
      SQLSERVER_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze
    end
  end
end
