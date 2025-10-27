MacOS Installation
==================

Installing Swiftarr on Your Computer\*

\* If your computer is a Macintosh

We recommend using [Homebrew](https://brew.sh) to install packages. Homebrew is a MacOS package manager, similar to `apt` or `yum`. During installation we'll also use Swift Package Manager (SPM), although SPM is really for source code packages whereas Homebrew is mostly for compiled products that could be installed with an installation app.

Installation
------------

### Toolchain

Swiftarr is Swift code, so you'll need the swift compiler toolchain installed. You have a few options for this:

#### Xcode

Install Xcode. It includes the Swift toolchain by default.

#### Swiftly

Swiftly is a Swift version manager for all platforms, a-la `nvm` from NodeJS or `rvm` from Ruby. It's easy to install:

```shell
brew install swiftly
```

The first time you run `swiftly` it will set itself up and insert itself into your shell. Restart your terminal when it's done. You should see something like this when you run `swiftly list`:

```
Installed release toolchains
----------------------------
Swift 6.2.0 (in use)

Installed snapshot toolchains
-----------------------------

Available system toolchains
---------------------------
xcode
```

At the root of this repository run `swiftly install`. This will read the `.swift-version` file then install/activate the correct toolchain version. This will automatically activate when you're working in that directory. You can confirm by running `swift --version`:

```
Apple Swift version 6.2 (swift-6.2-RELEASE)
Target: arm64-apple-macosx15.0
Build config: +assertions
```

### Library Dependencies

Swiftarr uses GD for image manipulation, and also links with jpeglib directly because of cases where GD is bad at its job. GD uses jpeglib, but chooses to ignore orientation directives in jpeg files, which necessitates a workaround.

```shell
brew install gd
```

### Configuration (Optional)

The code defaults let this run out of the box. However you may wish to customize your installation. If so, make a copy of the `Template.env` environment setup file in `Sources/swiftarr/seeds/Private Swiftarr Config`. Name it with the name of your environment (typically `development.env`). No changes are immediately needed but you can fill in passwords and such with private values if you want. See [Configuration](configuration.html) for details.

### Service Dependencies

Swiftarr uses both Postgres and Redis as database stores. You'll need both of these databases up and running. You can do this by running one or both natively (on your workstation just like other apps) or with Docker containers. Choose your favorite solution.

#### Natively (Brew)

Install the services:

```shell
brew install postgresql@18 redis
```

Then start them:

```shell
brew services run   # Run without adding to system login.
# -- or --
brew services start # Run and add to system login.
```

Postgres requires setting up a user. If you made changes to your environment configuration above, fill in those values instead. Otherwise use these defaults. Enter `swiftarr` as the password for the user.

```shell
createuser-18 swiftarr -P
createdb-18 swiftarr -O swiftarr
```

#### Containerized (Docker)

This assumes you have [Docker Desktop](https://www.docker.com/products/docker-desktop/) set up and functioning on your workstation.

```shell
scripts/instance.sh up -d postgres redis
```

### Build & Run

At this point you should be able to build the app in your preferred tool.

#### CLI

If you have a particular environment, add `--env <your-environment-name>`.

1. Build the app with `swift build`.

2. Run database migration with `swift run swiftarr migrate`. Hit `y` when prompted.

3. Run `swift run swiftarr serve`. If it works, it'll tell you `Server starting on http://127.0.0.1:8081`.

#### Xcode

1. Add a new scheme called `migrate` and target of `swiftarr`. 

2. Edit that scheme and under the `Run` step `Run` action add an argument to be pased on launch: `migrate`

3. Run the `migrate` scheme. Hit `y` in the Debug area when it asks you if you want to do a bunch of migrations.

Once `migrate` completes successfully, switch to the `swiftarr` scheme and run it. If it works, it'll tell you `Server starting on http://127.0.0.1:8081`.

#### VS Code

Ensure you have the [Swift Extension](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) installed.

1. Perform a migration using the CLI instructions above.

2. In the `Run & Debug` select `Debug swiftarr` and run it. The lower panel will switch from `Terminal` to `Debug Console` which is useless. Go back to the `Terminal` and you should see `Server starting on http://127.0.0.1:8081`.

Additional Information
----------------------

### Environment files

When launching Swiftarr from the command line, use `swift run swiftarr serve --env production` with the environment you want to use. `development` is the default; if you're only doing development builds you probably don't need to make a development.env file. If this is a publicly accessible install, you should make a copy of the `Template.env` Environment setup file in `Sources/swiftarr/seeds/Private Swiftarr Config` folder, name it with the name of your environment and fill in passwords and such with private values.

The git repo is configured to ignore all files in the `Sources/swiftarr/seeds/Private Swiftarr Config` directory other than the Template.env file. This is on purpose; don't check in your custom .env files.

There are several predefined environments:

- `development` is the default
- `production` and `testing` also predefined by Vapor
- You can also create and name custom environments.

In the environment file, the values that you should be sure to set include:

- `DATABASE_PASSWORD`
- `REDIS_PASSWORD`
- `ADMIN_PASSWORD`
- `ADMIN_RECOVERY_KEY`
- `THO_PASSWORD`
- `THO_RECOVERY_KEY`
- `SWIFTARR_USER_IMAGES`