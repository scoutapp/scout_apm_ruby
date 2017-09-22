# 2.3.0

Note: ScoutApm Agent version 2.2.0 was the initial ScoutProf agent that was
determined quickly to be a big enough change to warrant the move to 3.0. We are not
reusing that version number to avoid confusion.

* Deeper database query instrumentation. The agent now collects app-wide
  database usage on every call. This will allow you to better identify
  persistently slow queries, and capacity bottlenecks.
* Optimize the approach used during recording each request to avoid unnecessary
  work, improving performance

# 2.1.32

* Better naming when using Resque + ActiveJob
* Better naming when using Sidekiq + DelayedExtension

# 2.1.31

* Better detection of Resque queue names
* Fix passing arguments through Active Record instrumentation. (Thanks to Nick Quaranto for providing the fix)
* Stricter checks to prevent agent from starting in Rails console

# 2.1.30

* Add Resque support.

# 2.1.29

* Add `scm_subdirectory` option. Useful for when your app code does not live in your SCM root directory.

# 2.1.28

* Changes to app server load data

# 2.1.27

* Don't attempt to call `current_layer.type` on nil

# 2.1.26

* Bug fix [4b188d6](https://github.com/scoutapp/scout_apm_ruby/commit/4b188d698852c86b86d8768ea5b37d706ce544fe)

# 2.1.25

* Automatically instrument API and Metal controllers.

# 2.1.24

* Capture additional layers of application backtrace frames. (From 3 -> 8)

# 2.1.23

* Extend Mongoid instrumentation to 6.x

# 2.1.22

* Add DevTrace support for newest 4.2.x and 5.x versions of Rails

# 2.1.21

* Fix edge case, causing DevTrace to fail
* Add debug tooling, allowing custom functions to be inserted into the agent at
  key points.

# 2.1.20

* Add a `detailed_middleware` boolean configuration option to capture
  per-middleware data, as opposed to the default of aggregating all middleware
  together.  This has a small amount of additional overhead, approximately
  10-15ms per request.

# 2.1.19

* Log all configuration settings at start when log level is debug
* Tune DelayedJob class name detection

# 2.1.18

* Max layaway file threshold limit

# 2.1.17

* Additional logging around file system usage

# 2.1.16

* Extract the name correctly for DelayedJob workers run via ActiveJob

# 2.1.15

* Limit memory usage for very long running requests.

# 2.1.14

* Add TrackedRequest#ignore_request! to entirely ignore and stop capturing a
  certain request. Use in your code by calling:
    ScoutApm::RequestManager.lookup.ignore_request!

# 2.1.13

* Rework Delayed Job instrumentation to not interfere with other instruments.

# 2.1.12

* Revert 2.1.11's Delayed Job change - caused issues in a handful of environments

# 2.1.11

* Support alternate methods of launching Delayed Job

# 2.1.10

* Fix issue getting a default Application Name when it wasn't explicitly set

# 2.1.9

* Send raw histograms of response time, enabling more accurate 95th %iles
* Raw histograms are used in Apdex calculations
* Gzip payloads
* Fix Mongoid (5.0) + Mongo (2.1) support
* Initial Delayed Job support
* Limit max metric size of a trace to 500.


# 2.1.8

* Adds Git revision detection, which is reported on app load and associated with transaction traces

# 2.1.7

* Fix allocations extension compilation on Ruby 1.8.7

# 2.1.6

* Support older versions of Grape (0.10 onward)
* Vendor rusage library
* Fix double-exit that caused error messages when running under Passenger

# 2.1.5

* Be less strict loading Rails environments that don't have a matching
  scout_apm.yml section. Previously we raised, now we log and continue
  to load with the ENV settings
* Fix a memory leak in error recovery code
* Fix a minor race condition in data coordination between processes.
  * There was a tiny sliver of a window where a lock wasn't held, and it caused
    an exception to be raised.

# 2.1.4

* Enhance regular expression that determines if a backtrace line is "inside"
  the application
    * Avoids labeling vendor/ as part of the monitored app

# 2.1.3

* Less noisy output on errors with Context
  * Not logging errors w/nil keys or values
  * Bumping log level down from WARN => INFO on errors
* Fix error with complicated AR queries
  * Caused high log noise
* Sidekiq instrumentation changes to handle a variety of edge cases

# 2.1.2

* Applies `Rails.application.config.filter_parameters` settings to reported transaction trace uris
* Fix incompatibility with ResqueWeb and middleware instrumentation

# 2.1.1

* Fix an issue with AR instrumentation and complex queries
* Fix use of configuration option `data_file`
* Update unit tests

# 2.1.0

* Added ignore key to configuration to entirely ignore an endpoint. No traces
  or metrics will be collected. Useful for health-check endpoints.
* Better logging for DevTrace

# 2.0.0

* Reporting object allocation & mem delta metrics and mem delta for requests and jobs.
* Collecting additional fields for transactions:
  * hostname
  * seconds_since_startup (larger memory increases and other other odd behavior more common when close to startup)
* Remove unused & old references to Stackprof
* Fixing exception on load if no config file is provided
* DevTrace BETA

# 1.6.8

* Don't wait on a sleeping thread during shutdown

# 1.6.7

* Mongoid bugfixes

# 1.6.6

* Bugfix related to DB detection

# 1.6.5

* Add Mongoid 5.x support
* Fix autodetection of mysql databases

# 1.6.4

* Add Grape instrumentation
* Handle DATABASE_URL configurations better
* Change default (undeteced) database to Postgres (was Mysql)

# 1.6.3

* Handle nil ignore_traces when ignoring trace patterns

# 1.6.2

* Use a more flexible approach to storing "Layaway Files" (the temporary data
  files the agent uses).

# 1.6.1

* Remove old & unused references to Stackprof. Prevent interaction with intentional usage of Stackprof

# 1.6.0

* Dynamic algorithm for selecting when to collect traces. Now, we will collect a
  more complete cross-section of your application's performance, dynamically
  tuned as your application runs.
* Record and report 95th percentiles for each action
* A variety of bug fixes

# 1.5.5

* Handle backslash escaped quotes inside mysql strings.

# 1.5.4

* Fix issue where error counts were being misreported
* Politely ignore cases when `request.remote_ip` raises exceptions.

# 1.5.3

* Fix another minor bug related to iso8601 timestamps

# 1.5.2

* Force timestamps to be iso8601 format

# 1.5.1

* Add `ignore_traces` config option to ignore SlowTransactions from certain URIs.

# 1.5.0

* Background Job instrumentation for Sidekiq and Sidekiq-backed ActiveJob
* Collecting backtraces on n+1 calls

# 1.4.6

* Defend against a nil

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
