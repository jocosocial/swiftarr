Installation
============

Requirements
------------
There are five requirements for either running an instance of `swiftarr` or development itself.

* the [`libgd`](http://libgd.github.io) library
* a recent [Swift](https://swift.org) toolchain (recommend 5.5 or later)
* the [Vapor](http://vapor.codes) framework
* an instance of [PostgreSQL](https://www.postgresql.org)
* an instance of [Redis](https://redis.io)

A recent version of [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12) is also required for
development. (This is not strictly necessary, but if you walk your own Swift development path, add
"self-sufficiency" to the list.)

Swiftarr also uses libjpeg directly, but libjpeg should get installed when installing libgd.

Mac
---

### Basics

Swiftarr uses both Postgres and Redis as database stores. You'll need both of these databases up and running.

Swiftarr uses GD for image manipulation, and also links with jpeglib directly because of cases where GD is bad at its job. GD uses jpeglib, but chooses to ignore orientation directives in jpeg files, which necessitates a workaround.

Swiftarr is Swift code, so you'll need the swift compiler toolchain installed. If you're on a Mac, just install Xcode.

Not absolutely necessary, but I've been using [Homebrew](https://brew.sh) to install packages. Homebrew is a MacOS package manager, similar to apt or yum. During installation we'll also use Swift Package Manager (SPM), although SPM is really for source code packages, whereas Homebrew is mostly for compiled products that could be installed with an installation app.

You can also use Docker to install and run the database services. Docker is kinda-sorta a VM. It's a container solution for running server services, popular because there's lots of services that are Dockerized and you just grab the container and launch them. You'll still need to get the compiled libraries with Homebrew or similar.

### Part 1: Getting all the Parts Together

These install steps assume you have git and Xcode already, and are installing with the intent of doing at least some work on the server. 

1. Clone the Swiftarr repo with Git. [Get it here.](https://github.com/challfry/swiftarr/)
2. You’ll need to either run `swift package update` or “Update to latest package versions” within Xcode.

#### Using Homebrew

1. Install Postgres. `brew install postgres`
2. Install Redis: `brew install redis`. 
3. Install GD: I used `brew install gd`.
4. `brew services run` or `brew services start` to launch the databases

#### Using Docker

1. Install Docker [Link](https://www.docker.com/).
2. Run ./scripts/instance.sh up from the swiftarr directory to create and launch postgres and redis Docker containers.
3. Be sure to get libgd and libjpeg installed.

### Part 2: Configure, Build and Run

If this is a publicly accessible install, you should make a copy of the `Template.env` Environment setup file in `Sources/App/Run/Private Swiftarr Config` folder, name it with the name of your environment and fill in passwords and such with private values.

#### Building with Xcode

1. Build and run the Migrate scheme in Xcode. Hit y in the Debug area when it asks you if you want to do a bunch of migrations.
2. Once migrate completes successfully, switch to the 'Run' scheme and run it. If it works, it'll tell you "Server starting on http://192.168.0.1:8081"

#### Building from the Command Line

If you have a particular environment, add `--env <your-environment-name>`.

1. `vapor run migrate`, you should see a list of migrations that'll be run--hit `y`.
2. `vapor run serve` If you don't have an environment file that defines the hostname to serve from, add the `--hostname` parameter.

### More Info on Postgres

During Postgres install you'll need to make a Postgres user. You'll then need to set up Swiftarr to auth with that user and password. You can look at the fn `databaseConnectionConfiguration()` in `configure.swift` to see the relevant environment variables.

You'll also need to create the `swiftarr` database. `CREATE DATABASE swiftarr` from the psql command line should suffice.

### More info On Redis

If you install redis locally you'll need to run `redis-server` from the command line to get it up and running.

### More info on Environment files

When launching Swiftarr from the command line, use:

`vapor run --env production`

with the environment you want to use. `development` is the default; if you're only doing development builds you probably don't need to make a development.env file. If this is a publicly accessible install, you should make a copy of the `Template.env` Environment setup file in `Sources/App/Run/Private Swiftarr Config` folder, name it with the name of your environment and fill in passwords and such with private values.

The git repo is configured to ignore all files in the `Sources/App/Run/Private Swiftarr Config` directory other than the Template.env file. This is on purpose; don't check in your custom .env files.

There are several predefined environments:
- `development` is the default
- `production` and `testing` also predefined by Vapor
- `heroku` is a custom (to Vapor) environment defined by Swiftarr
- You can also create and name custom environments.

In the environment file, the values that you should be sure to set include:

- DATABASE_PASSWORD
- REDIS_PASSWORD
- ADMIN_PASSWORD
- ADMIN_RECOVERY_KEY
- THO_PASSWORD
- THO_RECOVERY_KEY
- SWIFTARR_USER_IMAGES

### Apple Silicon

If you're running on Apple Silicon, you need ARM versions of the libraries you link against. Mostly this means GD and jpeglib. Homebrew will install these, but it puts them in /opt/homebrew/Cellar instead of in /usr/local/Cellar. I had to massage the include and linker paths when building on an ARM mac. I'll eventually fix this up by including both paths in the project. This also means that you may run into problems doing Release builds as it'll try to build both ARM and X86/64 and make a fat binary. Soon™.

Linux
-----
This guide was written based on Fedora 34 (Red Hat). Some adjustments 
will need to be made for other distros (such as Ubuntu/Debian/etc).

### Prerequisites
1. You will need an instance of PostgreSQL (postgres) and Redis. It is HIGHLY
   recommended to use the Dockerized instances provided by `scripts/docker-compose-instance.yml`
   and its wrapper (`scripts/instance.sh`). If you want natively-installed
   instances of these applications you are on your own.

2. Several packages and libraries are required. Install these with your 
   package manager.
   ```
   sudo dnf install -y gd-devel libjpeg-turbo-devel swift-lang
   ```

3. This project uses the [Vapor](https://docs.vapor.codes/) web framework for Swift.
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
1. From the root of this repo:
   ```
   vapor build
   # or
   swift build
   ```

### Run
1. Ensure that the prereqs from above are running.
   ```
   ~ # scripts/instance.sh up -d            
   Creating network "swiftarr_default" with the default driver
   Creating swiftarr_postgres_1 ... done
   Creating swiftarr_redis_1    ... done
   ```

2. If you are populating a fresh database then you'll need to run a migration.
   to get some data.
   See the [Vapor docs](https://docs.vapor.codes/4.0/fluent/overview/#migrate) for details.
   This will be interactive so enter `y` at the prompt.
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

4. Run the server!
   ```
   vapor run
   # or
   swift run
   ```
   You should see a line akin to `Server starting on http://127.0.0.1:8081`
   which tells you where to point your web browser.

Docker
-------
This assumes you already have Docker or an equivalent OCI-compatible runtime
available to you. And `docker-compose` (or equivalent).

### Prerequisites
1. You need to decide on your runtime configuration:
   
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
   you'll need to create config files in `/Sources/Run/Private Swiftarr Config` based on
   the `Docker-Template.env`. See [Installation Notes](https://github.com/challfry/swiftarr/wiki/Installation-Notes#more-info-on-environment-files)
   for more details on what this does.
   
2. Docker-Compose < 1.26.0 has a bug that causes `env_file` processing to not escape values correctly. If you see strange behavior like timeouts or bad database configuration check your version. 1.25.6 is broken and 1.28.6 works.

3. I assume that your user is a part of the `docker` group and can run `docker` commands without issue. If this is a problem see the Docker instructions for adding
   that group to the system and getting yourself to be a part of it. While everything could probably work under `sudo` it has not been tested.

### Build
This only applies to the Linux-Testing or Stack configurations.

1. `docker-compose` will handle the building of the image.
   ```
   scripts/stack.sh -e production build [--no-cache]
   ```

### Run
1. `docker-compose` will similarly handle creating the whole stack.
   ```
   scripts/stack.sh -e production up [-d]
   ```
   The database is initially populated based on the environment that you specified.

   By default, this will expose the application at http://localhost:8081 assuming 
   all went well.

2. When you are done you can terminate and optionally delete everything using the same tooling.
   ```
   scripts/stack.sh -e production down [-v]
   ```

### Manual Database Migration
1. If you set `AUTO_MIGRATE` to `false` in your config and wish to perform a manual migration,
   you can do this by calling:
   ```
   scripts/stack.sh -e development run web /app/Run migrate --yes
   ```
2. Then you can restart the initial container that was created and died because
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
1. Perform a local build.
2. Extract the `/app/.build` contents from a previous Docker build.

To achieve the second option above:
1. Do an online Docker build.
   ```
   scripts/stack.sh -e production build
   ```

2. Look in the log for the image ID of the builder that it used. In this example it is `74f20d50b6a6`.
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

3. Create a temporary container based on that image to copy the files from. It helps to give it a human name but that is optional.
	 ```
   docker run --name buildertemp 74f20d50b6a6
   ```
   This will detatch and exist in the background. We will delete it later but if you get distracted you're on your own for cleanup.

4. Extract the package and workspace state. Note the trailing slash on the destination.
   ```
   mkdir ./.build
   docker cp buildertemp:/app/.build/workspace-state.json ./.build/
   docker cp buildertemp:/app/.build/checkouts ./.build/
   ```

5. Verify that you now have a `./.build` that looks like this:
   ```
   ls -l .build
   total 16K
   drwxr-xr-x. 29 grant grant 4.0K Jan 27 14:13 checkouts
   -rw-r--r--.  1 grant grant 8.9K Jan 27 14:13 workspace-state.json
   ```

6. Stop and remove the temporary container since we don't need it anymore.
   ```
   docker rm buildertemp
   ```

Once this is complete if you were to re-run the `scripts/stack.sh -e production build` it would trigger a new build since the builder will
detect that you've changed the source of the Swift dependencies (from internet pulls to local files). It will want to rebuild but you'll be
able to do so without downloading anything from the internet. This can be observed by initiating the build and doing a packet capture against
it. For example:

```bash
# In terminal #1
scripts/stack.sh -e production build

# In terminal #1
docker ps
docker inspect ${name_or_id_of_the_running_builder_container} | grep IPAddress
sudo tcpdump -nn -i any host 172.17.0.2 # or whatever the IP is
```

