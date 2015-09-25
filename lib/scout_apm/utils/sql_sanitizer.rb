require 'scout_apm/environment'

# Removes actual values from SQL. Used to both obfuscate the SQL and group
# similar queries in the UI.
module ScoutApm
  module Utils
    class SqlSanitizer
      if ScoutApm::Environment.instance.ruby_187?
        require 'scout_apm/utils/sql_sanitizer_regex_1_8_7'
      else
        require 'scout_apm/utils/sql_sanitizer_regex'
      end
      include ScoutApm::Utils::SqlRegex

      attr_reader :sql
      attr_accessor :database_engine

      def initialize(sql)
        @sql = scrubbed(sql.dup)
        @database_engine = ScoutApm::Environment.instance.database_engine
      end

      def to_s
        case database_engine
        when :postgres then to_s_postgres
        when :mysql    then to_s_mysql
        when :sqlite   then to_s_sqlite
        end
      end

      private

      def to_s_postgres
        sql.gsub!(PSQL_PLACEHOLDER, '?')
        sql.gsub!(PSQL_VAR_INTERPOLATION, '')
        sql.gsub!(PSQL_REMOVE_STRINGS, '?')
        sql.gsub!(PSQL_REMOVE_INTEGERS, '?')
        sql.gsub!(PSQL_IN_CLAUSE, 'IN (?)')
        sql.gsub!(MULTIPLE_SPACES, ' ')
        sql.gsub!(TRAILING_SPACES, '')
        sql
      end

      def to_s_mysql
        sql.gsub!(MYSQL_VAR_INTERPOLATION, '')
        sql.gsub!(MYSQL_REMOVE_SINGLE_QUOTE_STRINGS, '?')
        sql.gsub!(MYSQL_REMOVE_DOUBLE_QUOTE_STRINGS, '?')
        sql.gsub!(MYSQL_REMOVE_INTEGERS, '?')
        sql.gsub!(MYSQL_IN_CLAUSE, '?')
        sql.gsub!(MULTIPLE_QUESTIONS, '?')
        sql.gsub!(TRAILING_SPACES, '')
        sql
      end

      def to_s_sqlite
        sql.gsub!(SQLITE_VAR_INTERPOLATION, '')
        sql.gsub!(SQLITE_REMOVE_STRINGS, '?')
        sql.gsub!(SQLITE_REMOVE_INTEGERS, '?')
        sql.gsub!(MULTIPLE_SPACES, ' ')
        sql.gsub!(TRAILING_SPACES, '')
      end

      def has_encodings?(encodings=['UTF-8', 'binary'])
        encodings.all?{|enc| Encoding.find(enc) rescue false}
      end

      def scrubbed(str)
        return '' if !str.is_a?(String) || str.length > 1000 # safeguard - don't sanitize or scrub large SQL statements
        return str if !str.respond_to?(:encode) # Ruby <= 1.8 doesn't have string encoding
        return str if str.valid_encoding? # Whatever encoding it is, it is valid and we can operate on it
        ScoutApm::Agent.instance.logger.debug "Scrubbing invalid sql encoding."
        if str.respond_to?(:scrub) # Prefer to scrub before we have to convert
          return str.scrub('_')
        elsif has_encodings?(['UTF-8', 'binary'])
          return str.encode('UTF-8', 'binary', :invalid => :replace, :undef => :replace, :replace => '_')
        end
        ScoutApm::Agent.instance.logger.debug "Unable to scrub invalid sql encoding."
        ''
      end

    end
  end
end
