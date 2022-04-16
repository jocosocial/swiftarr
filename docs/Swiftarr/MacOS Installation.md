MacOS Installation
==================

Installing Swiftarr on Your Computer\*
\* If your computer is a Macintosh

## Basics

Swiftarr uses both Postgres and Redis as database stores. You'll need both of these databases up and running.

Swiftarr uses GD for image manipulation, and also links with jpeglib directly because of cases where GD is bad at its job. GD uses jpeglib, but chooses to ignore orientation directives in jpeg files, which necessitates a workaround.

Swiftarr is Swift code, so you'll need the swift compiler toolchain installed. If you're on a Mac, just install Xcode.

Not absolutely necessary, but I've been using [Homebrew](https://brew.sh) to install packages. Homebrew is a MacOS package manager, similar to apt or yum. During installation we'll also use Swift Package Manager (SPM), although SPM is really for source code packages, whereas Homebrew is mostly for compiled products that could be installed with an installation app.

You can also use Docker to install and run the database services. Docker is kinda-sorta a VM. It's a container solution for running server services, popular because there's lots of services that are Dockerized and you just grab the container and launch them. You'll still need to get the compiled libraries with Homebrew or similar.

## Part 1: Getting all the Parts Together

These install steps assume you have git and Xcode already, and are installing with the intent of doing at least some work on the server. 

1. Clone the Swiftarr repo with Git. [Get it here.](https://github.com/challfry/swiftarr/)
2. You’ll need to either run `swift package update` or “Update to latest package versions” within Xcode.

### Using Homebrew

1. Install Postgres. `brew install postgres`
2. Install Redis: `brew install redis`. 
3. Install GD: I used `brew install gd`.
4. `brew services run` or `brew services start` to launch the databases

### Using Docker

1. Install Docker [Link](https://www.docker.com/).
2. Run ./scripts/instance.sh up from the swiftarr directory to create and launch postgres and redis Docker containers.
3. Be sure to get libgd and libjpeg installed.

## Part 2: Configure, Build and Run

If this is a publicly accessible install, you should make a copy of the `Template.env` Environment setup file in `Sources/App/Run/Private Swiftarr Config` folder, name it with the name of your environment and fill in passwords and such with private values.

### Building with Xcode

1. Build and run the Migrate scheme in Xcode. Hit y in the Debug area when it asks you if you want to do a bunch of migrations.
2. Once migrate completes successfully, switch to the 'Run' scheme and run it. If it works, it'll tell you "Server starting on http://192.168.0.1:8081"

### Building from the Command Line

If you have a particular environment, add `--env <your-environment-name>`.

1. `vapor run migrate`, you should see a list of migrations that'll be run--hit `y`.
2. `vapor run serve` If you don't have an environment file that defines the hostname to serve from, add the `--hostname` parameter.

## More Info on Postgres

During Postgres install you'll need to make a Postgres user. You'll then need to set up Swiftarr to auth with that user and password. You can look at the fn `databaseConnectionConfiguration()` in `configure.swift` to see the relevant environment variables.

You'll also need to create the `swiftarr` database. `CREATE DATABASE swiftarr` from the psql command line should suffice.

## More info On Redis

If you install redis locally you'll need to run `redis-server` from the command line to get it up and running.

## More info on Environment files

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

## Apple Silicon

If you're running on Apple Silicon, you need ARM versions of the libraries you link against. Mostly this means GD and jpeglib. Homebrew will install these, but it puts them in /opt/homebrew/Cellar instead of in /usr/local/Cellar. I had to massage the include and linker paths when building on an ARM mac. I'll eventually fix this up by including both paths in the project. This also means that you may run into problems doing Release builds as it'll try to build both ARM and X86/64 and make a fat binary. Soon™.