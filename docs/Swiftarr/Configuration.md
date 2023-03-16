Configuration
=============

Runtime Environment
-------------------
Swiftarr can be run in several environment modes:

* **Development**: Seeds sample testing data, adds performance testing users, default log level of INFO.
* **Production**: No sample testing data, no testing users, default log level of WARNING.

"In general" local builds stick with `development` mode whereas container images are built with `production` mode.

Each environment gets configured by setting a config file in `Sources/App/seeds/Private Swiftarr Config`.

Instance
--------
The Docker Instance deployment configuration provides containerized service dependencies for Swiftarr. In
`Sources/App/seeds/Private Swiftarr Config` copy the `Template.env` to your desired runtime environment (example: `development.env`). You must then fill in the blanks for passwords, keys, etc.
* Database and Redis configuration must match what is configured in `scripts/docker-compose-instance.yml`.
* User passwords (such as `ADMIN_PASSWORD`) can be anything you want. Recovery keys can be one or more words.
* `SWIFTARR_IP` should be set to `127.0.0.1` for localhost access or `0.0.0.0` so anything on your network can access (subject to local firewall). Other interface IP addresses can be used if you wish.

Stack
-----

Server Deployment
-----------------