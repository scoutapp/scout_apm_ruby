# ScoutApm

A Ruby gem for detailed Rails application performance analysis. Metrics are reported to [Scout](https://scoutapp.com), a hosted application monitoring service. 

## Getting Started

Install the gem:

    gem install scout_apm
    
Signup for a [Scout](https://apm.scoutapp.com) account and copy the config file to `RAILS_ROOT/config/scout_apm.yml`.

Your config file should look like:

    common: &defaults
      name: YOUR_APPLICATION_NAME
      key: YOUR_APPLICATION_KEY
      monitor: true

    production:
      <<: *defaults

## Docs

For the complete list of supported frameworks, Rubies, etc, see our [help site](http://help.apm.scoutapp.com/).

## Help

Email support@scoutapp.com if you need a hand.
