# ScoutApm Ruby Agent

[![Build Status](https://travis-ci.org/scoutapp/scout_apm_ruby.svg?branch=master)](https://travis-ci.org/scoutapp/scout_apm_ruby)

A Ruby gem for detailed Rails application performance analysis. Metrics are
reported to [Scout](https://scoutapp.com), a hosted application monitoring
service.

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
