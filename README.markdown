# ScoutApm Ruby Agent

[![Build Status](https://github.com/scoutapp/scout_apm_ruby/actions/workflows/test.yml/badge.svg)](https://github.com/scoutapp/scout_apm_ruby/actions)

A Ruby gem for detailed Rails application performance monitoring 📈. Metrics, errors and transaction traces are
reported to [Scout](https://www.scoutapm.com), a hosted application monitoring
service. We have a free plan for small apps and a 14-day all-access trial to test out all
the features. If you want to send us Rails logs, add our [other
gem](https://github.com/scoutapp/scout_apm_ruby_logging) and we will correlate them with
your performance data!

## What's the special sauce? 🤔

The Scout agent is engineered to do some wonderful things:

* A unique focus on identifying those hard-to-investigate outliers like memory bloat, N+1s, and user-specific problems. [See an example workflow](http://scoutapp.com/newrelic-alternative).
* [Low-overhead](http://blog.scoutapp.com/articles/2016/02/07/overhead-benchmarks-new-relic-vs-scout)
* Production-Safe profiling of custom code via [ScoutProf](https://docs.scoutapm.com/#scoutprof) (BETA).

## Getting Started

Add the gem to your Gemfile

    gem 'scout_apm'

Add [a version of the `parser` gem that supports your version of Ruby](https://github.com/whitequark/parser?tab=readme-ov-file#backwards-compatibility). For example, if you're on Ruby 3.3.0:

    gem 'parser', '~> 3.3.0.0'

Update your Gemfile

    bundle install

Signup for a [Scout](https://scoutapm.com/users/sign_up?utm_source=github&utm_medium=github&utm_campaign=scout_apm_ruby)
account and put the provided config file at `RAILS_ROOT/config/scout_apm.yml`.

Your config file should look like:

    common: &defaults
      name: YOUR_APPLICATION_NAME
      key: YOUR_APPLICATION_KEY
      monitor: true

    test:
      monitor: false

    production:
      <<: *defaults

## Error Monitoring

All of our accounts include Error Monitoring with 5000 errors/month free. To enable it, add the following to your `scout_apm.yml`:

```yaml
# Common/dev/production/etc. whereever you would like to start trying it
# monitor: true should also be required to ensure your App exists in Scout
errors_enabled: true
```

## DevTrace Quickstart

To use DevTrace, our free, no-signup, in-browser development profiler:

1. Add the gem to your Gemfile:

```ruby
# Gemfile
gem 'scout_apm'
```

2. Start your Rails app with the SCOUT_DEV_TRACE environment variable:

```
SCOUT_DEV_TRACE=true rails server
```

## How to test gem locally

* Point your gemfile at your local checkout: `gem 'scout_apm', path: '/path/to/scout_apm_ruby`
* Compile native code: `cd /path/to/scout_apm_ruby && bundle exec rake compile`


## Docs

For the complete list of supported frameworks, Rubies, configuration options
and more, see our [help site](https://scoutapm.com/docs).

## Help

Email support@scoutapm.com if you need a hand.
