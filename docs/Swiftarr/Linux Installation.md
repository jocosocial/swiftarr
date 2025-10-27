Linux Installation
==================

Installing Swiftarr on Your Computer\*

\* If your computer runs Linux or Windows (oh the irony...)

Installation
------------

### Prerequisites
Ubuntu 24.04 may require the following packages to be installed first: `libncurses6`, `build-essential`.

### Toolchain

Swiftarr is Swift code, so you'll need the swift compiler toolchain installed. Swiftly is a Swift version manager for all platforms, a-la `nvm` from NodeJS or `rvm` from Ruby. It's easy to install and is the preferred method by the Swift community. Follow step 1 of of the [Swift.org Linux Install](https://www.swift.org/install/linux/)

```shell
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
tar zxf swiftly-$(uname -m).tar.gz && \
./swiftly init --quiet-shell-followup && \
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" && \
hash -r
```

The first time you run `swiftly` it will set itself up and insert itself into your shell. You should see something like this when you run `swiftly list`:

```
Installed release toolchains
----------------------------
Swift 6.2.0 (in use) (default)

Installed snapshot toolchains
----------------------------
```

At the root of this repository run `swiftly install`. This will read the `.swift-version` file then install/activate the correct toolchain version. This will automatically activate when you're working in that directory. You can confirm by running `swift --version`:

```
Swift version 6.2 (swift-6.2-RELEASE)
Target: x86_64-unknown-linux-gnu
```

### Library Dependencies

Swiftarr uses GD for image manipulation, and also links with jpeglib directly because of cases where GD is bad at its job. GD uses jpeglib, but chooses to ignore orientation directives in jpeg files, which necessitates a workaround.

Install these with your system package manager:
* Fedora: `gd-devel` `libjpeg-turbo-devel`
* Ubuntu: `libgd-dev` `libjpeg-dev`

### Configuration (Optional)

The code defaults let this run out of the box. However you may wish to customize your installation. If so, make a copy of the `Template.env` environment setup file in `Sources/swiftarr/seeds/Private Swiftarr Config`. Name it with the name of your environment (typically `development.env`). No changes are immediately needed but you can fill in passwords and such with private values if you want. See [Configuration](configuration.html) for details.

### Service Dependencies

Swiftarr uses both Postgres and Redis as database stores. You'll need both of these databases up and running. Docker is the preferred solution to this.

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

#### VS Code

Ensure you have the [Swift Extension](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) installed. If you are in a WSL environment, it must be installed "on the remote side".

1. Perform a migration using the CLI instructions above.

2. In the `Run & Debug` select `Debug swiftarr` and run it. You should see `Server starting on http://127.0.0.1:8081` in the lower panel (either `Debug Console` or `Terminal`)
