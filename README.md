# `swiftarr`

<p align="center">
    <br>
    <a href="LICENSE">
        <img src="http://img.shields.io/badge/license-MIT-brightgreen.svg" alt="MIT License">
    </a>
    <a href="https://swift.org">
        <img src="http://img.shields.io/badge/swift-5.1-brightgreen.svg" alt="Swift 5.1">
    </a>
</p>
<br>

`swiftarr` is the asynchronous back-end to Twit-arr, implementing API v3. `swiftarr` is written entirely in
(unsurprisingly) Swift, using the Vapor 3 framework, and the SwiftGD wrapper for image processing. `swiftarr`
runs on either macOS or Linux.

## Getting Started

If you're here for something other than curiosity or to provide [feedback](https://github.com/grundoon/swiftarr/issues),
you're probably either developing an API client or maybe even thinking about [getting involved]
(https://github.com/grundoon/swiftarr/blob/master/CONTRIBUTING.md) with `swiftarr` development itself.

### Requirements

There are five requirements for either running an instance of `swiftarr` or development itself.

* the [`libgd`](http://libgd.github.io) library
* a recent [Swift](https://swift.org) toolchain (recommend 5.1.x or later)
* the [Vapor](http://vapor.codes) framework
* an instance of [PostgreSQL](https://www.postgresql.org)
* an instance of [Redis](https://redis.io)

A recent version of [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12) is also required for
development. (This is not strictly necessary, but if you walk your own Swift development path, add
"self-sufficiency" to the list.)

### Quickstart - macOS

If running on macOS with Xcode installed, the easiest way to get an instance up and running is via
[Docker](https://www.docker.com/products/docker-desktop).

1. Install Docker.
2. Install `libgd`.
    - On macOS using [Homebrew](https://brew.sh), simply `brew install gd`.
    - On linux, `apt-get libgd-dev` as root.
3. Install the [Vapor](http://docs.vapor.codes/3.0/install/macos/) toolbox. (I don't actually know if this is necessary
for just running an instance, and have no way to easily test that at the moment, but it *might* be needed to get the
correct SSL library and shimming for SwiftNIO.)
4. Download or clone the `switarr` [repository](https://github.com/grundoon/swiftarr).
5. Run `./scripts/instance.sh up` from the `swiftarr` directory to create and launch postgres and redis
Docker containers.
6. Generate the `swiftarr.xcodeproj` file, then open it in Xcode.

```shell
cd <swiftarr-directory>
swift package generate-xcodeproj
open ./swiftarr.xcodeproj
```

Make sure the selected Scheme is "My Mac" in Xcode, hit Run, and `swiftarr` should shortly be available at http://localhost:8081.
To shut down the Docker containers, `./scripts/instance.sh stop`.

Yes, that's a bunch the first time through and it does take some time. From here on out though, it's just a matter of
pulling the latest updates from the repository and regenerating the .xcodeproj file.

(more to come... )


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
