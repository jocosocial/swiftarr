## Contributing to `swiftarr`

### General

Anybody should feel free to open or comment on an [issue](https://github.com/grundoon/swiftarr/issues). This is
the preferred place to consolidate all discussion related specifically to the `swiftarr` API backend. Questions,
general feedback, suggestions, feature requests, bug reports and proposed changes are all fair game.

While it *is* the preferred location, a (free) GitHub account is required to participate there directly, so it is not
strictly necessary. The Twit-arr developers collectively participate in (or at least monitor with a reasonable amount
of attention) related Slack channels, the various FaceBook groups, and the feedback Forums within Twit-arr itself
when it is active, so any of those places would probably also be fine.

### Contributing Code

Contributions to `swiftarr` are absolutely welcome! Some general guidelines:

* Please fork, branch, and submit [pull requests](https://github.com/grundoon/swiftarr/pulls). Not even a primary
maintainer should be working on or pushing directly to the master branch.
* For changes that go beyond, say, simple documentation updates or typo corrections or straightforward bug
fixes, please first open an issue for discussion. A PR is far less likely to be rejected and more likely to merge
without conflict if we're all on the same page.
* Please do not take offense when changes are requested. There are many reasons this can occur, though it will
usually simply be related to maintaining a consistent coding style (see below). Sure a maintainer could "fix" it
themself, but we'd dfinitely prefer that you ultimately get full credit for the contribution.
* Please do not attempt to update the `docs/` in a pull request; leave that to the primary maintainer(s).
* Related, please do not modify the included `.jazzy.yaml` configuration file. That's a great example of
something that should first be discussed by opening an issue!

And possibly the two most important things:

* `swiftarr` is 100% documented in Swift Documentation Markup, which is both Xcode "Quick Help" compatible
(shows in the option-click popups and in the Quick Help Inspector side panel) and used by
[`jazzy`](https://github.com/realm/jazzy) to generate the HTML `docs/` directory. Please help uphold this standard;
there is abundant example already in there.
* `swiftarr` strives for 100% test coverage. For any new functionality, please provide a test if possible, and try
to include all branch cases (i.e. test the failure cases). Since we're not (currently anyway) running any continous
integration, it'd also be helpful (though not required) to run the full test suite to catch any possible breaking
changes before submitting a PR. Don't worry – testing, and the Xcode test framework in particular, can be new
territory for many and we're happy to help.

### Coding Style

Earlier iterations of `swiftarr` tended to gleefully flaunt some of the elegance achievable with Swift and the
Vapor framework sugar. Fun and pleasing to look at, yes – not to mention a vastly reduced line count from the
current – but it didn't exactly help make the code maintainable. So here we are.

The code is intended to be straightforward in nature, readable, and consistent in style. Syntax shortcuts are
generally avoided in deference to understandability for language and framework newcomers. There is no single
reference stye guide followed; it pulls from a number of respected ones and personal preferences.

* Indentation is 4 spaces. Not tabs, spaces.

* All names should be super-clear as to purpose or function. Prefer variable `passwordHash` and function
`generateRecoveryKey()` to `ph` and `genKey()`.
[swift.org](https://swift.org/documentation/api-design-guidelines/) has tons of thoughts on this stuff.  

* Naming conventions should be consistent. For example, endpoints generally accept data struct names of the
form `<Model><Action>Data` and return `<Action><Model>Data` (such as `UserCreateData` and
`CreatedUserData` in the case of user creation).

* When possible, incoming data should be validated using Vapor's
[`Validatable`](https://docs.vapor.codes/3.0/validation/overview/) protocol rather than in-line.

* Whitespace is good.

* When parameters begin to challenge the right margin and/or the reader of the code, prefer a multi-line format.
But don't use Xcode's pretty indentation style, because it can make things look like ass on GitHub.

```swift
let user = User(username: data.username, password: data.password, verification: data.registrationCode, ...) // NO

let user = User(username: data.username, // also NO
                password: data.password,
                verification: data.registratonCode,
                ...)

let user = User( // YES
    username: data.username,
    password: data.password,
    verification: data.registratonCode,
    ...
)
```

* 


