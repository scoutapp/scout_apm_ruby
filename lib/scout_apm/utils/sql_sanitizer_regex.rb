
module ScoutApm
  module Utils
    module SqlRegex
      MULTIPLE_SPACES    = %r|\s+|.freeze
      MULTIPLE_QUESTIONS = /\?(,\?)+/.freeze

      PSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*\z|.freeze
      PSQL_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      PSQL_REMOVE_INTEGERS = /(?<!LIMIT )\b\d+\b/.freeze
      PSQL_PLACEHOLDER = /\$\d+/.freeze
      PSQL_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze
      PSQL_AFTER_WHERE = /(?:WHERE\s+).*?(?:SELECT|\z)/im.freeze
      PSQL_AFTER_SET = /(?:SET\s+).*?(?:WHERE|\z)/im.freeze

      MYSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      MYSQL_REMOVE_INTEGERS = /(?<!LIMIT )\b\d+\b/.freeze
      MYSQL_REMOVE_SINGLE_QUOTE_STRINGS = %r{'(?:\\'|[^']|'')*'}.freeze
      MYSQL_REMOVE_DOUBLE_QUOTE_STRINGS = %r{"(?:\\"|[^"]|"")*"}.freeze
      MYSQL_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze

      SQLITE_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      SQLITE_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      SQLITE_REMOVE_INTEGERS = /(?<!LIMIT )\b\d+\b/.freeze

      # => "EXEC sp_executesql N'SELECT  [users].* FROM [users] WHERE (age > 50)  ORDER BY [users].[id] ASC OFFSET 0 ROWS FETCH NEXT @0 ROWS ONLY', N'@0 int', @0 = 10"
      SQLSERVER_EXECUTESQL = /EXEC sp_executesql N'(.*?)'.*/
      SQLSERVER_REMOVE_INTEGERS = /(?<!LIMIT )\b(?<!@)\d+\b/.freeze
      SQLSERVER_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze
    end
  end
end
