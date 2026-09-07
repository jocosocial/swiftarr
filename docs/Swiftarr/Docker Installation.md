Docker Installation
===================

This assumes you already have Docker or an equivalent OCI-compatible runtime
available to you. And `docker-compose` (or equivalent).

Warning: Very little testing has been done with the Docker Compose plugin rather than the docker-compose script. Your mileage may vary when using the plugin.

Prerequisites
-------------

01. Docker-Compose < 1.26.0 has a bug that causes `env_file` processing to not escape values correctly. 
    If you see strange behavior like timeouts or bad database configuration check your version. 1.25.6 
    is broken and 1.28.6 works.

02. I assume that your user is a part of the `docker` group and can run `docker` commands without issue. 
    If this is a problem see the Docker instructions for adding that group to the system and getting 
    yourself to be a part of it. While everything could probably work under `sudo` it has not been tested.

Configure
---------

01. Create your own `production.env` in `Sources/swiftarr/seeds/Private Swiftarr Config`. 
    See [Configuration](configuration.html) for details.

Build
-----

This only applies to the Stack configurations.

01. `docker-compose` will handle the building of the image.

    ```
    scripts/stack.sh -e production build [--no-cache]
    ```

Run
---

01. `docker-compose` will similarly handle creating the whole stack.
    ```
    scripts/stack.sh -e production up [-d]
    ```
    The database is initially populated based on the environment that you specified. By default, this will
    expose the application at http://localhost:8081 assuming all went well.

02. When you are done you can terminate and optionally delete everything using the same tooling.
    ```
    scripts/stack.sh -e production down [-v]
    ```

Images
------
Postgres and Redis use Docker Official Images (`docker.io/library/postgres:15` and `docker.io/library/redis:7`).
Those tags are available for both AMD64 and ARM64. Containers run as the image users (`postgres` / `redis`), not root.

Redis does not take a password from an environment variable the way Bitnami did. The stack compose file passes
`--requirepass` from `REDIS_PASSWORD` in your env file. Postgres uses the Official `POSTGRES_DB` /
`POSTGRES_USER` / `POSTGRES_PASSWORD` names (aliased from `DATABASE_*` in `Docker-Template.env`).

Data directories differ from the old Bitnami layout (`/bitnami/postgresql` and `/bitnami/redis/data`).
Existing named volumes will not be read at the new paths (`/var/lib/postgresql/data` and `/data`). After
switching, recreate volumes and re-migrate:

```
scripts/instance.sh down -v
scripts/stack.sh -e production down -v
```
