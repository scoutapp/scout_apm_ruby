source "https://rubygems.org"

# Specify your gem's dependencies in scout_apm.gemspec
gemspec

gem "rake", ">= 12.3.3"

# i18n 1.15.0 started using Fiber storage (`Fiber.[]`), which only exists on
# Ruby 3.2+, so on older Rubies ActiveSupport blew up loading it with
# `NoMethodError: undefined method '[]' for Fiber:Class` (fixed upstream in
# 1.15.2). Gemfile.lock is gitignored, so CI resolves i18n fresh each run and is
# at the mercy of such transient bad releases on the pre-3.2 matrix. Keep those
# (EOL-track) Rubies pinned to the stable 1.14 line for a deterministic build.
gem "i18n", "< 1.15" if RUBY_VERSION < "3.2"
