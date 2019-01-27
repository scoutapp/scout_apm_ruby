source "https://rubygems.org"

# Specify your gem's dependencies in scout_apm.gemspec
gemspec

# Pin development dependencies more conservatively for Ruby 1.8.7
if RUBY_VERSION <= "1.8.7"
  gem "activesupport", "~> 3.2"
  gem "i18n", "~> 0.6.11"
  gem "pry", "~> 0.9.12"
  gem "rake", "~> 10.5"
end

group :development do
  gem "parser"
end
