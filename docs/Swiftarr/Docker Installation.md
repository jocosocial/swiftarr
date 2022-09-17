Docker Installation
===================

This assumes you already have Docker or an equivalent OCI-compatible runtime
available to you. And `docker-compose` (or equivalent).

Prerequisites
-------------

01. You need to decide on your runtime configuration:
   
    | Configuration | Description                                                         |
    |---------------|---------------------------------------------------------------------|
    | Instance      | Service dependencies only.                                          |
    | Stack         | Service dependencies and production-ready web server image.         |
   
    Each configuration has a corresponding shell script located in `/scripts` that is a 
    wrapper around `docker-compose` which will aid in getting up and running.
   
    If you are considering doing a Stack deployment you need to decide what environment you
    wish to run. Generally this is `development` or `production`. There isn't a ton of
    difference between the two other than initial database seeding and logging. Regardless,
    you'll need to create config files in `/Sources/App/seeds/Private Swiftarr Config` based on
    the `Docker-Template.env`. See [Installation Notes](https://github.com/challfry/swiftarr/wiki/Installation-Notes#more-info-on-environment-files)
    for more details on what this does.
   
02. Docker-Compose < 1.26.0 has a bug that causes `env_file` processing to not escape values correctly. 
    If you see strange behavior like timeouts or bad database configuration check your version. 1.25.6 
    is broken and 1.28.6 works.

03. I assume that your user is a part of the `docker` group and can run `docker` commands without issue. 
    If this is a problem see the Docker instructions for adding that group to the system and getting 
    yourself to be a part of it. While everything could probably work under `sudo` it has not been tested.

Build
-----

This only applies to the Stack configurations.

01. `docker-compose` will handle the building of the image.

    ```
    scripts/stack.sh -e production build [--no-cache]
    ```

Run
---

01. `docker-compose` will similarly handle creating the whole stack.\
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
As of 2022-07-31:

We desire to support both AMD64 and ARM64 architectures since this offers interoperability between M*-Mac
devs and Linux devs. Unfortunately the dependency ecosystem around ARM64 is somewhat fragmented. Bitnami,
who publish excellent images, do [not yet support ARM64 images](https://github.com/bitnami/charts/issues/7305). The
"Official" images (ie, `docker.io/library/*`) do support ARM64 but lack the convenience wrappers that publishers
often add (like setting Redis credentials, etc). Canonical started publishing a bunch of images that offer both
ARM64 support and convenience wrappers but they're still stamped Beta. Until Bitnami improves their ecosystem we're
gonna use the Ubuntu images.