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
      
## Supported Frameworks

* Rails 2.2 through Rails 4

## Supported Rubies

* Ruby 1.8.7 through Ruby 2.1.2

## Supported Application Servers

* Phusion Passenger
* Thin
* WEBrick
* Unicorn (make sure to add `preload_app true` to `config/unicorn.rb`)
* Rainbows
* Puma

## Help

Email support@scoutapp.com if you need a hand.
