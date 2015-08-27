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
