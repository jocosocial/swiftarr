<p align="center">
    <img src="https://user-images.githubusercontent.com/1342803/36623515-7293b4ec-18d3-11e8-85ab-4e2f8fb38fbd.png" width="320" alt="API Template">
    <br>
    <br>
    <a href="http://docs.vapor.codes/3.0/">
        <img src="http://img.shields.io/badge/read_the-docs-2196f3.svg" alt="Documentation">
    </a>
    <a href="https://discord.gg/vapor">
        <img src="https://img.shields.io/discord/431917998102675485.svg" alt="Team Chat">
    </a>
    <a href="LICENSE">
        <img src="http://img.shields.io/badge/license-MIT-brightgreen.svg" alt="MIT License">
    </a>
    <a href="https://circleci.com/gh/vapor/api-template">
        <img src="https://circleci.com/gh/vapor/api-template.svg?style=shield" alt="Continuous Integration">
    </a>
    <a href="https://swift.org">
        <img src="http://img.shields.io/badge/swift-5.1-brightgreen.svg" alt="Swift 5.1">
    </a>
</p>

About ...

## Getting Started

If you're here for something other than curiosity or to provide
[feedback](https://github.com/grundoon/swiftarr/issues), you're probably either developing an API client or
maybe even thinking about [getting involved](https://github.com/grundoon/swiftarr/blob/master/CONTRIBUTING.md)
with `swiftarr` development itself.

And if you're working on an API client there's a fair chance you're looking to run an instance of `swiftarr` to test
against (for documentation info, see further down this page). Let's discuss the development requirements first,
since it is also a valid approach to running a functional test instance.

### Development

The base assumption is that you're working on a reasonably modern macOS computer. (This is not strictly
necessary, but if you walk your own Swift development path, add "self-sufficiency" to the list of requirements.)
A complete development environment requires 5 things.

* a recent [Swift](https://swift.org) toolchain (recommend 5.1.x or later)
* a recent version of [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12)
(which will already include the Swift toolchain)
* the [Vapor](http://docs.vapor.codes/3.0/install/macos/) framework installed
* instances of [PostgreSQL](https://www.postgresql.org) running on both standard and test ports
* instances of [Redis](https://redis.io) running on both standard and test ports

#### Quickstart

Not to worry, it can all be much easier than that list makes it sound. Simply follow the instructions for installing
Vapor (use a current version of Xcode though, not the minimum requirement). Then fork a copy of this repository
and `git pull` that to your local machine. Generate the `swiftarr.xcodeproj` and open it.

```shell
cd <swiftarr-directory>
swift package generate-xcodeproj
open ./swiftarr.xcodeproj
```
In fact, using the installed Vapor Toolbox shortcut, the last two commands can be replaced by

```shell
vapor xcode -y
```
which you might prefer because the the .xcodeproj file needs to be regenerated *any time the underlying file
structure changes*. This is currently just part of life when working with Swift Package Manager projects.

`swiftarr` needs to be able to connect to the database engines, so before you hit the `Run` command you'll
need to have them available. You can certainly run them natively directly on your Mac (PostgreSQL is already
included with macOS and Redis will need to be installed), but using
[Docker](https://www.docker.com/products/docker-desktop) is a highly recommended approach and there's
a simple script provided to (hopefully) painlessly spin the databases up in Docker containers.

```shell
cd <swiftarr-directory>
./scripts/development.sh up
```
This will create and start containers for both PostgreSQL and Redis on their standard ports, as well as
containers on alternate ports for running the tests (`Test`) without destroying any data you'd like to keep.

```shell
docker ps    // should show all 4 containers "Up"
```
The script also accepts 'stop', 'start' and 'remove' as shortcut commands.

So not only does this result in a full `swiftarr` development environment, simply `Run` and you have a perfectly
functional instance of `swiftarr` for API client development (with the bonus ability to "see inside" the backend
as it runs). Or, if you prefer to just spin up an instance without all the rest **or aren't working in a macOS
environment at all**, skip down a few inches to the Deployment section.

#### Linux Testing

Testing during development within Xcode is pretty straightforward, but it is critical that the tests also be run
under the Linux environment in which it will run during production. See `CONTRIBUTING.md` way at the bottom
for necessary precursor info if you've added any tests. Then build and spin up a Swift container alongside the
test database ones, for which another script has been provided:

```shell
cd <swiftarr-directory>
./scripts/linux-testing.sh up
```

### Deployment

Docker

Bare Metal

Heroku

AWS


## Documentation

- **API_cheatsheet.md**: A quick endpoint reference for client development, including payload requirements and
return types.

- **docs/**: A complete API reference generated directly from the documentation markup within the source code,
in navigable HTML format.

- **source code**: The source code itself is, in every sense, the definitive documentation. It is thoroughly
documented, incorporating both formatted Swift Documentation Markup blocks (`///`) and organizational
`MARK`s used to generate the HTML `docs/` pages, as well as in-line comments (`//`) to help clarify flow, function,
and thought process. Maintainers and contributors are requested to adhere to the existing standards, or outright
improve upon them!

The `docs/` are generated using the awesome [`jazzy`](https://github.com/realm/jazzy).

The [Vapor](https://vapor.codes) framework has its own [API documentation](https://api.vapor.codes).


