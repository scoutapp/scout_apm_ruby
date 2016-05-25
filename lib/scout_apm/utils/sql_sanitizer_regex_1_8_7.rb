
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

      MYSQL_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      MYSQL_REMOVE_INTEGERS = /\b\d+\b/.freeze
      MYSQL_REMOVE_SINGLE_QUOTE_STRINGS = /'(?:\\'|[^']|'')*'/.freeze
      MYSQL_REMOVE_DOUBLE_QUOTE_STRINGS = /"(?:\\"|[^"]|"")*"/.freeze
      MYSQL_IN_CLAUSE = /IN\s+\(\?[^\)]*\)/.freeze

      SQLITE_VAR_INTERPOLATION = %r|\[\[.*\]\]\s*$|.freeze
      SQLITE_REMOVE_STRINGS = /'(?:[^']|'')*'/.freeze
      SQLITE_REMOVE_INTEGERS = /\b\d+\b/.freeze

    end
  end
end
