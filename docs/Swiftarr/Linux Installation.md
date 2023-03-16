Linux Installation
==================

Prerequisites
-------------

01. You will need an instance of PostgreSQL (postgres) and Redis. It is HIGHLY
    recommended to use the Dockerized instances provided by `scripts/docker-compose-instance.yml`
    and its wrapper (`scripts/instance.sh`). If you want natively-installed
    instances of these applications you are on your own.

02. Several packages and libraries are required. Install these with your 
    package manager.
    ```
    Fedora: gd-devel libjpeg-turbo-devel swift-lang
    Ubuntu: libgd-dev libjpeg-dev swiftlang (requires 3rd party repo)
    ```

Configure
---------

01. Create your own `development.env` in `Sources/App/seeds/Private Swiftarr Config`. 
    See [Configuration](configuration.html) for details.

Build
-----

01. From the root of this repo:
    ```
    swift build
    ```

Run
---

01. Ensure that the prereqs from above are running.
    ```
    ~ # scripts/instance.sh up -d postgres redis
    Creating network "swiftarr_default" with the default driver
    Creating swiftarr_instance_postgres_1 ... done
    Creating swiftarr_instance_redis_1    ... done
    ```

02. If you are populating a fresh database then you'll need to run a migration.
    to get some data. See the [Vapor docs](https://docs.vapor.codes/4.0/fluent/overview/#migrate) for details.
    ```
    swift run Run migrate --yes
    ```
    Example output:
    ```
    [0/0] Build complete!
    [ NOTICE ] Starting up in Development mode.
    ...
    The following migration(s) will be prepared:
    ...
    + App.SetInitialCategoryForumCounts on psql
    Would you like to continue?
    y/n>

    [ INFO ] Starting registration code import [database-id: psql]
    [ INFO ] Starting boardgame import [database-id: psql]
    ...
    [ INFO ] Imported 25000 karaoke songs. [database-id: psql]
    Migration successful
    ```

03. Run the server!
    ```
    swift run
    ```
    You should see a line akin to `Server starting on http://127.0.0.1:8081`
    which tells you where to point your web browser.
