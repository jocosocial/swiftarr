## Contributing to `swiftarr`

### General

Anybody should feel free to open or comment on an [issue](https://github.com/grundoon/swiftarr/issues). This is
the preferred place to consolidate all discussion related specifically to the `swiftarr` API backend. Questions,
general feedback, suggestions, feature requests, bug reports and proposed changes are all fair game.

While it *is* the preferred location, a (free) GitHub account is required to participate there directly, so it is not
strictly necessary. The Twit-arr developers collectively participate in (or at least monitor with a reasonable amount
of attention) related Slack channels, the various FaceBook groups, and the feedback Forums within Twit-arr itself
when it is active, so any of those would probably also be fine.

### Contributing Code

Contributions to `swiftarr` are absolutely welcome! Some general guidelines:

* Please fork, branch and submit [pull requests](https://github.com/grundoon/swiftarr/pulls). Not even a primary
maintainer should be working on or pushing directly to the master branch.
* For changes that go beyond, say, simple documentation updates or typo corrections or straightforward bug
fixes, please first open an issue for discussion. A PR is far less likely to be rejected and more likely to merge
without conflict if we're all on the same page.
* Please do not take offense when changes are requested. There are many reasons this can occur, though it will
usually simply be related to maintaining a consistent coding style (see below). Sure a maintainer could "fix" it
oneself, but we'd dfinitely prefer that you ultimately get full credit for the contribution.
* Please do not attempt to update the `docs/` in a pull request; leave that to the primary maintainer(s).
* Related, please do not attempt to modify the included `.jazzy.yaml` configuration file. That's' a great
example of something that should first be discussed by opening an issue.

### Coding Style


When possible, incoming data should be validated using Vapor's
[`Validatable`](https://docs.vapor.codes/3.0/validation/overview/) protocol rather than in-line.
