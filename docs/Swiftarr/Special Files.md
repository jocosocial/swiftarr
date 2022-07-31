Special Files
=============

Like most server projects, Swiftarr is a bunch of small packages that do specific things, and they all get glued together into an app. I mean this in the sense that iOS and Mac app projects tend to be a big clump of code that interacts with Apple system libs, plus maybe a couple of small packages on the side to do things like analytics and user tracking. With Swiftarr, if you pull all the small add-on packages away, there's hardly anything left.

Anyway, a bunch of those packages have their own *special file* in the Swiftarr repo, and if you can *find* the add-on that it's for, you can read the docs for that add-on and learn what the file does. But -- ha ha -- all too often you can't find the right place to look for the docs.

So I made this.

## In the Root dir

- `.DS_Store`: MacOS litters every directory with these. They should be gitignored, but someone probably checked one in.
- `.build`: Swift Package Manager has a build system that'll build your app, and when you use it, this is where all the build products go. Can be thrown away when not running the app to save space, or `swift package clean` should work. Note that when running using the `swift` command line toolchain, the built app will be (deep) inside this directory.
- `__pycache__`: This one's easy. Python bytecode files, probably here because of Locust. See `locustfile.py`
- `.dockerignore`: Swiftarr can run as a Docker image; if you're doing this you're probably also running Postgres and Redis as Docker images. This file just tells Docker to not Dockerize stuff it doesn't need.
- `.git`, `.gitignore`: Okay, you know these.
- `.jazzy.yaml`: Jazzy is a doc generator. This file tells Jazzy how we want our docs to look.
- `.swift-version`: Heroku uses this file to install a specific version of the Swift compiler toolchain on your Heroku node.
- `.swiftpm`: It's nice to see the SPM build system coming along so nicely. It'd be disappointing if all they did was take a bunch of Xcode project files in hidden subdirectories where nobody knows what they do, and replace them with a bunch of different hidden subdirectories full of files where nobody knows what they do.
- `DerivedData`: When building with Xcode, including `xcodebuild`, all the .o files, debug files, and built products will be placed in here. Like `.build`, the entire directory may be deleted when the app is not running.
- `Images`: User-uploaded images *may* be stored inside this folder. The actual location is configuration-dependent (see the `.env` files) but this is a good place for them as it's already gitignored. This folder can be thrown away when you do a database reset; just remember that the Postgres db contains filenames of files it expects to find here.
- `locustfile.py`: Locust is a load testing package for servers, written in Python. You'll need to install [Locust](http://locust.io) to use it. This particular file is set up to repeatedly make requests to ~100 of the most commonly used Swiftarr endpoints. The file does not validate the results; it's purpose is to load up the server with calls until all the CPUs are pegged.
- `Package.resolved`: This is where the Swift Package Manager keeps its list of all the dependent Swift packages (mostly parts of Vapor), and the versions it's currently building with.
- `Package.swift`: This is SPM's package manifest file. All the top-level dependencies Swiftarr needs to compile are listed, along with other parts that need to go into the app. [Swift.org](http://www.swift.org) has more about this. Importantly, SPM has a full toolchain on Mac, Linux and Windows.
- `Procfile`: [Heroku](http://heroku.com) uses this file to figure out how to launch your app. For us, it's just a Run command, making sure to set the environment to `heroku`. Nobody else uses this.
- `Prometheus`: [Prometheus](https://prometheus.io) is a server metrics platform. You can run the `prometheus` command line tool and then view metrics data in a browser. This can be used to monitor server health, track down bugs (e.g. bugs that only come from a specific client), and find routes whose response times are slow.
- `swiftarr.xcodeproj`: For the last 50 years, software engineers have been attempting to design a replacement for Makefiles that was less terrible. Xcode project files have succeeded in this regard, but it's a low bar. Their big failing (IMHO) is that it's almost impossible to do a manual git-merge with them. Sometimes auto-merge works and everything's fine, sometimes your project won't open anymore. But, if you have to look at the merge conflicts and try to resolve them -- it's best to reset your changes, take updates, and reapply the changes in Xcode.

## Inside `/scripts`

- `development.sh`: Bash script to start/stop the database containers, and also reset them. Wraps docker-compose calls.
- `docker-compose-instance.yml`:
- `docker-compose-stack.yml`:
- `Dockerfile`: Container image build specification.
- `generatedocs.sh`: Shell script that uses swift doc to generate documentation files for the API from inline header comments.
- `instance.sh`: Shell script for staring/stopping/resetting the databases in on a Mac.

## Inside `/Sources/Run/Private Swiftarr Config`

- `Template.env`: This is the template for setting up environment files for Swiftarr, when running Swiftarr as a local process. Environment files contain server and DB passwords, and shouldn't be checked into Git. Set up an environment by copying this file and filling in the various fields as appropriate.
- `Docker-Template.env`: Same idea as `Template.env`, but for running Swiftarr inside a Docker container.

## Inside `/Sources/App/Controllers/Structs`

Almost all the data types used by the API are in these files. Most of the data types are Swift structs that get serialized to/from JSON, and the struct member names map exactly to what's in the JSON. Values with an ending `?` are optional, and won't be emitted in JSON if their value is NULL (that is, they won't be { "value": null }). A struct member with an Enum value type have its enum value converted to a string that matches the name of the enum value.

Swift allows for several sorts of data transformations with JSON serialization, and also allows for enums to be parsed as integers or renamed when converted to JSON. We're not doing those things with the API structs, for improved clarity.

## Inside `/Sources/App/Resources`

Resource files that Swiftarr needs. Located here instead of at the root because of how the Swift Package Manager's build system works. Files in the `/Views` subdirectory are Leaf template files for the front end HTML.

## Inside `Sources/App/gdOverrides`

We've customized some parts of how GD works; mostly pertaining to JPEG file handling.