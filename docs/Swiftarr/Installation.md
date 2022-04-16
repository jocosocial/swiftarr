Installation
============

MacOS
-----

NSEverything

Linux
-----

This guide was written based on Fedora 34 (Red Hat). Some adjustments 
will need to be made for other distros (such as Ubuntu/Debian/etc).

### Prerequisites

01. You will need an instance of PostgreSQL (postgres) and Redis. It is HIGHLY
    recommended to use the Dockerized instances provided by `scripts/docker-compose-instance.yml`
    and its wrapper (`scripts/instance.sh`). If you want natively-installed
    instances of these applications you are on your own.

02. Several packages and libraries are required. Install these with your 
    package manager.
    ```
    sudo dnf install -y gd-devel libjpeg-turbo-devel swift-lang
    ```

03. This project uses the [Vapor](https://docs.vapor.codes/) web framework for Swift.
    While Linux is a supported platform there are no packages available for the Toolbox
    so it must be built. Follow the instructions at https://docs.vapor.codes/4.0/install/linux/
    To summarize:
    ```
    git clone https://github.com/vapor/toolbox
    cd toolbox
    git checkout 18.3.3 # This was the latest at the time of writing.
    sudo make install
    ```

### Build

01. From the root of this repo:
    ```
    vapor build
    # or
    swift build
    ```

### Run

01. Ensure that the prereqs from above are running.
    ```
    ~ # scripts/instance.sh up -d            
    Creating network "swiftarr_default" with the default driver
    Creating swiftarr_postgres_1 ... done
    Creating swiftarr_redis_1    ... done
    ```

02. If you are populating a fresh database then you'll need to run a migration.
    to get some data. See the [Vapor docs](https://docs.vapor.codes/4.0/fluent/overview/#migrate) for details.
    ```
    # Note there is no `swift` eqivalent here. You need the vapor CLI.
    vapor run migrate --yes
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
    vapor run
    # or
    swift run
    ```
    You should see a line akin to `Server starting on http://127.0.0.1:8081`
    which tells you where to point your web browser.

Docker
------

This assumes you already have Docker or an equivalent OCI-compatible runtime
available to you. And `docker-compose` (or equivalent).

### Prerequisites

01. You need to decide on your runtime configuration:
   
    | Configuration | Description                                                         |
    |---------------|---------------------------------------------------------------------|
    | Development   | Service dependencies and secondary instances of each for testing.   |
    | Instance      | Service dependencies only.                                          |
    | Linux-Testing | Service dependencies and web server image that will run test suite. |
    | Stack         | Service dependencies and production-ready web server image.         |
   
    Each configuration has a corresponding shell script located in `/scripts` that is a 
    wrapper around `docker-compose` which will aid in getting up and running. All scripts
    should be run from the root of the repo (not from within the scripts directory).
   
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

### Build

This only applies to the Linux-Testing or Stack configurations.

01. `docker-compose` will handle the building of the image.

    ```
    scripts/stack.sh -e production build [--no-cache]
    ```

### Run

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

### Manual Database Migration

01. If you set `AUTO_MIGRATE` to `false` in your config and wish to perform a manual migration,
    you can do this by calling:
    ```
    scripts/stack.sh -e development run web /app/Run migrate --yes
    ```

02. Then you can restart the initial container that was created and died because
    there was no DB for it at the time.
    ```
    scripts/stack.sh -e development restart web
    ```

### Offline Incremental Builds

You will have had to go through an online build at least once in order for this to work.

Docker will cache:
* The bage images (`swift`, `ubuntu`, `postgres`, etc).
* The layers in which we install packages from Apt repos.

But this leaves local Swift package caching. There are a couple files that get seeded 
into `./.build` when you do a local build (`swift build` or `vapor build` from a dev machine)
that we can put in place to ensure an offline Docker-based build will also work. Specifically
they are:
* `./build/workspace-state.json`
* `./build/checkouts`

The `Dockerfile.stack` will automatically attempt to copy them into the image build
context if they exist. As long as they don't change that image layer will cache and
and there will be a performance benefit in doing incremental Docker builds. Otherwise
it'll just have to copy them into a new builder image (not the end of the world).

To seed your `./build` directory you can do one of two things:
01. Perform a local build.
02. Extract the `/app/.build` contents from a previous Docker build.

To achieve the second option above:
01. Do an online Docker build.

    ```
    scripts/stack.sh -e production build
    ```

02. Look in the log for the image ID of the builder that it used. In this example it is `74f20d50b6a6`.
    ```
	[950/951] Compiling Redis Application+Redis.swift
    remark: Incremental compilation has been disabled: it is not compatible with whole module optimization[952/953] Compiling App AdminController.swift
    remark: Incremental compilation has been disabled: it is not compatible with whole module optimization[954/955] Compiling Run main.swift
    [956/956] Linking Run
    [956/956] Build complete!
    Removing intermediate container f9ead447694a
    ---> 74f20d50b6a6 ### HEY THIS IS THE IMAGE ID YOU SEEK ###
    Step 13/29 : FROM ubuntu:18.04 as base
    ---> 886eca19e611
    ```

03. Create a temporary container based on that image to copy the files from. It helps to give it a human name but that is optional.
	 ```
    docker run --name buildertemp 74f20d50b6a6
    ```

    This will detatch and exist in the background. We will delete it later but if you get distracted you're on your own for cleanup.

04. Extract the package and workspace state. Note the trailing slash on the destination.
    ```
    mkdir ./.build
    docker cp buildertemp:/app/.build/workspace-state.json ./.build/
    docker cp buildertemp:/app/.build/checkouts ./.build/
    ```

05. Verify that you now have a `./.build` that looks like this:
    ```
    ls -l .build
    total 16K
    drwxr-xr-x. 29 grant grant 4.0K Jan 27 14:13 checkouts
    -rw-r--r--.  1 grant grant 8.9K Jan 27 14:13 workspace-state.json
    ```

06. Stop and remove the temporary container since we don't need it anymore.
    ```
    docker rm buildertemp
    ```

Once this is complete if you were to re-run the `scripts/stack.sh -e production build` it would trigger a new build since the builder will
detect that you've changed the source of the Swift dependencies (from internet pulls to local files). It will want to rebuild but you'll be able to do so without downloading anything from the internet. This can be observed by initiating the build and doing a packet capture against it. For example:
```
# In terminal #1
scripts/stack.sh -e production build

# In terminal #1
docker ps
docker inspect ${name_or_id_of_the_running_builder_container} | grep IPAddress
sudo tcpdump -nn -i any host 172.17.0.2 # or whatever the IP is
```