# 1.5.1

* Collecting memory metrics on slow transactions
* Collecting additional fields for slow transactions:
  * hostname
  * seconds_since_startup (larger memory increases and other other odd behavior more common when close to startup)

# 1.5.0

* Background Job instrumentation for Sidekiq and Sidekiq-backed ActiveJob
* Collecting backtraces on n+1 calls

# 1.4.6

* Defend against a nil

# 1.5.0

* Background Job instrumentation for Sidekiq and Sidekiq-backed ActiveJob

# 1.4.5

* Instrument Elasticsearch
* Instrument InfluxDB

# 1.4.4

* Instrument Mongoid
* Instrument Redis

# 1.4.3

* Add a to_s call to have HTTPClient work with URI objects.  Thanks to Nicolai for providing the change!

# 1.4.2

* Add HTTPClient instrumentation

# 1.4.1

* Fix JSON encoding of special characters

# 1.4.0

* Release JSON reporting

# 1.3.4

* Fix backtracking issue with on of the SQL sanitization regexes

# 1.3.3

* Handling nil scope in LayerSlowTransactionConverter

# 1.3.0

* Lazy metric naming for ActiveRecord calls

# 1.2.13

* SQL Sanitation-Related performance improvements:
  * Lazy sanitation of SQL queries: only running when needed (a slow transaction is recorded)
  * An SQL sanitation performance improvement (strip! vs. gsub!)
  * Removing the TRAILING_SPACES regex - not used across all db engines and adds a bit more overhead

# 1.2.12

* Add uri_reporting option to report bare path (as opposed to fullpath). Default is 'fullpath'; set to 'path' to avoid exposing URL parameters.  

# 1.2.11

* Summarizing middleware instrumentation into a single metric for lower overhead.
* If monitoring isn't enabled:
  * In ScoutApm::Middleware, don't start the agent
  * Don't start background worker

# 1.2.10

* Improve exit handler. It wasn't being run during shutdown in some cases.

# 1.2.9

* Uses ActiveRecord::Base.configurations to access database adapter across all versions of Rails 3.0+.

# 1.2.8

* Enhance shutdown code to be sure we save current-minute metrics and minimize
  the amount of work necessary.

# 1.2.7

* Clarifying that Rails3 instrumentation also supports Rails4

# 1.2.6

* Fix a bug when determining the name of metrics for ActiveRecord queries

# 1.2.5

* Instrument ActionController::Base instead of ::Metal.  This allows us to
  track time spent in before and after filters, and requests that return early
  from before filters.
* Avoid parsing backtraces for requests that don't end up as Slow Transactions

# 1.2.4.1

* Reverting backtrace parser threshold back to 0.5 (same as < v1.2 agents)

# 1.2.4

* Removing layaway file validation in main thread
* Fixing :force so agent will start in tests
* Rate-limiting slow transactions to 10 per-reporting period

# 1.2.3

* Trimming metrics from slow requests if there are more than 10.

# 1.2.2

* Collapse middleware recordings to minimize payload size
* Limit slow transactions recorded in full detail each minute to prevent
  overloading payload.

# 1.2.1

* Fix a small issue where the middleware that attempts to start the agent could
  mistakenly detect that the agent was running when in fact it wasn't.

# 1.2.0

* Middleware tracing - Track time in the Rack middleware that Rails sets up
* Queue Time tracking - Track how much time is spent in the load balancer
* Solidify support for threaded app servers (such as Puma or Thin)
* Major refactor of internals to allow more flexibility for future features
* Several bug fixes

# 1.0.0

* General Availability
* More robust Application Server detection

# 0.9.7

* Added Cloud Foundry detection
* Added hostname config option
* Reporting PaaS in app server load (Heroku or Cloud Foundry).
* Fallback to a middleware to launch the agent if we can't detect the
  application server for any reason
* Added agent version to checkin data

# 0.9.6

* Fix more 1.8.7 syntax errors

# 0.9.5

* Fix 1.8.7 syntax error

# 0.9.4

* Detect database connection correctly on Rails 3.0.x
* Detect and warn if the old ScoutRails plugin is installed, since it causes an
  conflict.

# 0.9.3

* Parse SQL correctly when using PostGIS
* Quiet overly aggressive logging during startup.
  You can still turn up logging by setting the SCOUT_LOG_LEVEL environment variable to 'DEBUG'
* Various minor bug fixes and clarification of log messages

# 0.9.2

* Internal changes and bug fixes.

# 0.9.1.1

* Minor change in Stackprof processing code. Any exception that happens there
  should never propagate out to the application

# 0.9.1

Big set of features getting merged in for this release.

* StackProf support!  Get visibility into your Ruby code. On Ruby 2.1+, just
  add `gem 'stackprof'` to your Gemfile.
* Deploy tracking! Compare your application's response time, throughput and
  error rate between different releases.  At the bottom of your Capistrano
  deploy.rb file, add `require 'scout_apm'` and we do the rest.
* Log message overhaul. Removed a lot of the noise, clarified messages.

# 0.9.0

* Come out of alpha, and release a beta version.

# 0.1.16

* Initial support for Sinatra monitoring.

# 0.1.15

* Add new `application_root` option to override the autodetected location of
  the application.

# 0.1.14

* Add new `data_file` option to configuration, to control the location of the
  temporary data file.  Still defaults to log/scout_apm.db.  The file location
  must be readable and writeable by the owner of the Ruby process

# 0.1.13

* Fix support for ActiveRecord and ActionController instruments on Rails 2.3

# 0.1.12

* Fix Puma integration. Now detects both branches of preload_app! setting.
* Enhance Cpu instrumentation

# 0.1.11

* Post on-load application details in a background thread to prevent potential
  pauses during app boot

# 0.1.10

* Prevent instrumentation in non-web contexts. Prevents agent running in rails
  console, sidekiq, and similar contexts.
* Send active Gems with App Load message

# 0.1.9

* Added environment (production, development, etc) to App Load message
* Bugfix in Reporter class

# 0.1.8

* Ping APM on Application Load
* Fix compatibility with Ruby 1.8 and 1.9

# 0.1.7

* Ability to ignore child calls in instrumentation.

# 0.1.6

* Fix issues with Ruby 1.8.7 regexes

# 0.1.5

* SQL sanitization now collapses IN (?,?,?) to a single (?)

# 0.1.4

* Tweaks to Postgres query parsing
* Fix for missing scout_apm.yml file causing rake commands to fail because of a missing log file.

# 0.1.3.1

* Adds Puma support
* Fix for returning true for unicorn? and rainbows? when they are included in the Gemfile but not actually serving the app.

# 0.1.3

* Adds capacity calculation via "Instance/Capacity" metric. 
* Tweaks tracing to still count a transaction if it results in a 500 error and includes it in accumulated time.
* Adds per-transaction error tracking (ex: Errors/Controller/widgets/index)

# 0.1.2

* Adds Heroku support:
  * Detects Heroku via the 'DYNO' environment variable
  * Defaults logger to STDOUT
  * uses the dyno name vs. the hostname as the hostname
* Environment vars with "SCOUT_" prefix override any settings specified in the config file.

# 0.1.1

* Store the start time of slow requests.

# 0.1.0

* Boom.
