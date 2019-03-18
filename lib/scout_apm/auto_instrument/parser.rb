
begin
  # In order for this to work, you must add `gem 'parser'` to your Gemfile.
  require 'parser/current'

  raise LoadError, "Parser::TreeRewriter was not defined" unless defined?(Parser::TreeRewriter)
rescue LoadError
  warn "ScoutApm::AutoInstrument requires `gem 'parser'` to be present: #{$!}. Skipping."
end
