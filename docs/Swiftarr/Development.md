Development
===========

These are the tools you'll need to get started building Swiftarr for yourself.

Swift
-----
Swift runs on MacOS or Linux. If you are unfamiliar with the language we suggest the [Codecademy Learn Swift](https://www.codecademy.com/learn/learn-swift) course.
It's free and pretty quick for those who have experience with languages such as Java or C.

MacOS
-----

### Requirements

There are five requirements for either running an instance of `swiftarr` or development itself.

* the [`libgd`](http://libgd.github.io) library
* a recent [Swift](https://swift.org) toolchain (recommend 5.6 or later)
* the [Vapor](http://vapor.codes) framework
* an instance of [PostgreSQL](https://www.postgresql.org)
* an instance of [Redis](https://redis.io)

A recent version of [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12) is also required for
development. (This is not strictly necessary, but if you walk your own Swift development path, add
"self-sufficiency" to the list.)

Swiftarr also uses libjpeg directly, but libjpeg should get installed when installing libgd.

### Quickstart - macOS

If running on macOS with Xcode installed, the easiest way to get an instance up and running is via
[Docker](https://www.docker.com/products/docker-desktop).

1. Install Docker.
2. Install `libgd`. With [Homebrew](https://brew.sh) installed, simply `brew install gd`.
3. Install the [Vapor](http://docs.vapor.codes/) toolbox. (I don't actually know if this is necessary
for just running an instance, and have no way to easily test that at the moment, but it *might* be needed to get the
correct SSL library and shimming for SwiftNIO.)
4. Download or clone the `switarr` [repository](https://github.com/jocosocial/swiftarr).
5. Run `scripts/instance.sh up -d redis postgres` from the `swiftarr` directory to create and launch postgres and redis
Docker containers.
6. Create your own `development.env` in `Sources/App/seeds/Private Swiftarr Config`. See [Configuration](configuration.html) for details.
7. Open the swiftarr.xcodeproj file.
8. Run the "Migrate" scheme to configure the databses, or

```shell
xcodebuild -project "swiftarr.xcodeproj" -scheme "Migrate"
./DerivedData/swiftarr/Build/Products/Debug/Run migrate
```

You'll be asked to approve a bunch of migrations; these mostly create database tables. 

9. Set the scheme to "Run/My Mac" in Xcode, hit Run, and `swiftarr` should shortly be available at http://localhost:8081.
To shut down the Docker containers, `scripts/instance.sh stop`.

Yes, that's a bunch the first time through and it does take some time. From here on out though, it's just a matter of
pulling the latest updates from the repository and regenerating the .xcodeproj file.

#### Generating a new Xcode Project

Swiftarr uses a Package.swift dependency management file; like a million other package-managers it loads in other source code
and manages dependencies. Xcode can also direclty open and build Package.swift files in a way similar to project files; 
except you can't set up build scripts or do a bunch of other project-y things. To regen the project:

```shell
cd <swiftarr-directory>
swift package generate-xcodeproj
open ./swiftarr.xcodeproj
```

Then, in Target Settings for the App Target, select the Build Phases tab. Add a Copy Files phase copying "Resources" and 
"Seeds" directories to the "Products Directory" destination.

One of the many Xcode quirks that confuses developers not used to it is that Xcode puts the built app and all the buildfiles
in the /DerivedData folder. The Copy Files script copies all the Leaf templates, javascript, css, images, into /DerivedData
on each build and the running app uses the copies, NOT the files in /Resources and /Seeds. But, the copy happens every build,
even if no sources changed. So, while running the server, you can edit a Leaf template or some JS, hit command-B to build, 
reload the page, and see the changes. 

Linux
-----

### Requirements

You will need to install the Swift compiler and runtime. This is probably available as a package
via your system packager (`swift-lang`) or via https://www.swift.org/download/

After that you will likely want the following tools:
* https://github.com/apple/swift-format
* https://github.com/jpsim/SourceKitten
* https://github.com/realm/jazzy/

Consult their READMEs for installation.

### Quickstart - Linux
If running on Linux with VSCode or in a terminal, the easiest way to get an instance up and running is via
[Docker](https://www.docker.com/products/docker-desktop).

1. Install Docker.
2. Install the various binary dependencies.
    * Fedora: gd-devel libjpeg-turbo-devel
    * Ubuntu: libgd-dev libjpeg-dev
3. Download or clone the `switarr` [repository](https://github.com/jocosocial/swiftarr).
4. Run `scripts/instance.sh up -d postgres redis` from the repo directory to create and launch Postgres and Redis
Docker containers. You can omit the `postgres redis` portion of the command to get additional instance containers.
5. Build the codebase using VSCode or in a terminal with `swift build`. This could take a while if it's the first time.
6. Create your own `development.env` in `Sources/App/seeds/Private Swiftarr Config`. See [Configuration](configuration.html) for details.
7. Perform an initial database migration. This only needs to be done once or whenever there are additional migrations to apply. `swift run Run migrate [--yes]`. Note the two run's with differing case.
8. Start the app with `swift run Run serve` and you should be greeted with a line akin to `Server starting on http://127.0.0.1:8081`.
