__Rails application monitoring is avaiable by invite-only @ Scout.__

# ScoutApm

A Ruby gem for detailed Rails application performance analysis. Metrics are reported to [Scout](https://scoutapp.com), a hosted server and application monitoring service. For general server monitoring, see our [server monitoring agent](https://github.com/scoutapp/scout-client).

![Scout Rails Monitoring](https://img.skitch.com/20120714-frkr9i1pyjgn58uqrwqh55yfb8.jpg)

## Getting Started

Install the gem:

    gem install scout_apm
    
Signup for a [Scout](https://scoutapp.com) account and copy the config file to `RAILS_ROOT/config/scout_apm.yml`.

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

## Help

See our [troubleshooting tips](https://scoutapp.com/info/support_app_monitoring) and/or email support@scoutapp.com if you need a hand.
