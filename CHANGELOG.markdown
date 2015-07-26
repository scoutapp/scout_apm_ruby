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