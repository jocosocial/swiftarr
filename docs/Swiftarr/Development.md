Development
===========

These are the tools you'll need to get started building Swiftarr for yourself.

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
5. Run `./scripts/instance.sh up` from the `swiftarr` directory to create and launch postgres and redis
Docker containers.
6. Open the swiftarr.xcodeproj file.
7. Run the "Migrate" scheme to configure the databses, or

```shell
xcodebuild -project "swiftarr.xcodeproj" -scheme "Migrate"
./DerivedData/swiftarr/Build/Products/Debug/Run migrate
```

You'll be asked to approve a bunch of migrations; these mostly create database tables. 

8. Set the scheme to "Run/My Mac" in Xcode, hit Run, and `swiftarr` should shortly be available at http://localhost:8081.
To shut down the Docker containers, `./scripts/instance.sh stop`.

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

You will need to install the Swift compiler and runtime. This is probably available as a package
via your system packager (`swift-lang`) or via https://www.swift.org/download/

After that you will need the following tools:
* https://github.com/vapor/toolbox
* https://github.com/apple/swift-format
* https://github.com/jpsim/SourceKitten
* https://github.com/realm/jazzy/

Consult their READMEs for installation.

More SoonTM