# ScoutApm Ruby Agent

[![Build Status](https://travis-ci.org/scoutapp/scout_apm_ruby.svg?branch=master)](https://travis-ci.org/scoutapp/scout_apm_ruby)

A Ruby gem for detailed Rails application performance analysis. Metrics and transaction traces are
reported to [Scout](https://scoutapp.com), a hosted application monitoring
service.

## What's the special sauce? 🤔

Glad you asked! The Scout agent can do some special things:

* A unique focus on identifying those hard-to-investigate outliers like memory bloat, N+1s, and user-specific problems. [See an example workflow](http://scoutapp.com/newrelic-alternative).
* [Low-overhead](http://blog.scoutapp.com/articles/2016/02/07/overhead-benchmarks-new-relic-vs-scout)
* View your performance metrics during development with [DevTrace](http://help.apm.scoutapp.com/#devtrace) and in production via [server_timing](https://github.com/scoutapp/ruby_server_timing).
* Production-Safe profiling of custom code via [ScoutProf](http://help.apm.scoutapp.com/#scoutprof) (BETA).

## Getting Started

Add the gem to your Gemfile

    gem 'scout_apm'

Update your Gemfile

    bundle install

Signup for a [Scout](https://apm.scoutapp.com) account and put the provided
config file at `RAILS_ROOT/config/scout_apm.yml`.

Your config file should look like:

    common: &defaults
      name: YOUR_APPLICATION_NAME
      key: YOUR_APPLICATION_KEY
      monitor: true

    production:
      <<: *defaults

## Docs

For the complete list of supported frameworks, Rubies, configuration options
and more, see our [help site](http://help.apm.scoutapp.com/).

## Help

Email support@scoutapp.com if you need a hand.
