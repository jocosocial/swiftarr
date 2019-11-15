## Contributing to `swiftarr`

### General

Anybody should feel free to open or comment on an [issue](https://github.com/grundoon/swiftarr/issues)! This is
the preferred place to consolidate discussion related specifically to the `swiftarr` API backend. Questions,
general feedback, suggestions, feature requests, bug reports, and proposed changes are all fair game.

While it *is* the preferred location, a (free) GitHub account is required to participate there directly. The Twit-arr
developers collectively participate in (or at least monitor to some extent) related Slack channels, the various
Facebook groups, and the feedback forums within Twit-arr itself when it is active, so any of those places are
also fine-ish.

### Contributing Code

Contributions to `swiftarr` are absolutely welcome! Some general guidelines:

* Please fork, branch, and submit [pull requests](https://github.com/grundoon/swiftarr/pulls). Not even a primary
maintainer should be working on or pushing directly to the master branch.
* For changes that go beyond, say, simple documentation updates or typo corrections or straightforward bug
fixes, please first open an issue for discussion. A PR is far less likely to be rejected and more likely to merge
without conflict if we're all on the same page.
* Please do not take offense when changes are requested. There are many reasons this can occur, though it will
usually simply be related to maintaining a consistent coding style (see below). Sure a maintainer could "fix" it
themself, but we'd definitely prefer that you ultimately get full credit for the contribution.
* Please do not attempt to update the `docs/` in a pull request; leave that to the primary maintainer(s).
* Related, please do not modify the included `.jazzy.yaml` configuration file. That's a great example of
something that should first be discussed by opening an issue!

And possibly the two most important things:

* `swiftarr` is 100% documented in Swift Documentation Markup, which is both Xcode "Quick Help" compatible
(shows in the option-click popups and in the Quick Help Inspector side panel) and used by
[`jazzy`](https://github.com/realm/jazzy) to generate the HTML `docs/` directory. Please help uphold this standard;
there is abundant example already in there.

* `swiftarr` strives for 100% test coverage. For any new functionality, please provide a test if possible, and try
to include all branch cases (i.e. test the failure cases). Since we're not (currently anyway) running any continuous
integration, it'd also be helpful (though not required) to run the full test suite to catch any possible breaking
changes before submitting a PR. Don't worry – testing, and the Xcode test framework in particular, can be new
territory for many and we're happy to help.

### Coding Style

Earlier iterations of `swiftarr` tended to gleefully flaunt some of the elegance achievable with Swift and the
Vapor framework sugar. Fun to write and pleasing to look at, yes – not to mention a vastly reduced line count from the
current – but it didn't exactly help make the code maintainable. So here we are.

The code is intended to be straightforward in nature, readable, and consistent in style. Syntax shortcuts are
generally avoided in deference to understandability for language and framework newcomers. There is no single
reference style guide followed; conventions informally pull from a number of respected ones, personal
preferences, and stepping back to view it all with maintainability at the forefront.

* Indentation is 4 spaces. Not tabs, spaces.

* All names should be super-clear as to purpose or function. Prefer variable `passwordHash` and function
`generateRecoveryKey()` to `ph` and `genKey()`.
[swift.org](https://swift.org/documentation/api-design-guidelines/) has opinions on this stuff.  

* Naming conventions should be consistent. For example, endpoints generally accept data struct names of the
form `<Model><Action>Data` and return `<CompletedAction><Model>Data` (such as `UserCreateData` and
`CreatedUserData` in the case of user creation). Test names alway start with `test` and generally follow an
endpont pattern (e.g. `testAuthLogin` for `/api/v3/auth/login`).

* If creating a new Model, try to keep the `Model.swift` clean by sticking to the essentials (such as properties,
initializers and any subtypes). Use `extension`s for everything else and place them in a separate
`Model+Extensions.swift` file.

* When creating a new Model, think about how it might be used to decide what type of `ID` is most appropriate.
In general, if it is something that a URL link might point to (such as a twarrt or forumPost), use a numeric to keep
things short; otherwise probably use a UUID.

* If creating a new `class`, mark it as a `final class` so that the compiler can fully optimize it.

* Alphabetize `func`s, `struct`s, etc. by name within their respective sections to help keep the code navigable.
This is not necessary within `XCTestCase` classes; just add to the end. Generally avoid messing with `// MARK:`s,
as a number are used to help organize the `docs/` generation.

* Avoid force-unwrapping optionals; there's virtually (if not literally) always a way around it. The only code that
should contain a `!` is test code, where you *want* things to fail.

* When practical, incoming data should be validated using Vapor's
[`Validatable`](https://docs.vapor.codes/3.0/validation/overview/) protocol rather than in-line. While custom 
`Validation` closures can be used for more complex handling than the built-in `Validator` operators provide,
the current intent is just to enforce data format here and handle any processing issues in-line.

* Whitespace is good.

* When parameters begin to challenge the right margin and/or the reader of the code, prefer a multi-line format.
But don't use Xcode's pretty indentation style, because it can make things look like ass on GitHub.

```swift
let user = User(username: data.username, password: passwordHash, recoveryKey: recoveryHash, ...) // NO

let user = User(username: data.username, // also NO
                password: passwordHash,
                recoveryKey: recoveryHash,
                ...)

let user = User( // YES
    username: data.username,
    password: passwordHash,
    recoveryKey: recoveryHash,
    ...
)
```

* Prefer multi-line format when there are multiple conditionals (yes, Xcode is pretty weird on the indentation in a
`guard` statement like this, but it's still way more readable than the option).

```swift
guard let toast = try? Breakfast.toast(.challah, slices: 2),
    let friedEggs = try? Breakfast.fry(.egg, count: 2),
    let cornedBeefHash = try? BCrypt.hash("cornedBeef") else {
        fatalError("another Sunday brunch ruined")
}
```

* When directly throwing an error, always include a return message for the client. If it is intended to inform the
client developer, make it clear what condition failed; if it is something that might be passed on to the end user,
write clearly and understandable to that audience. (And of course be sure to document the potential error
response  in a `/// - Throws: ...` block and include the branch condition in a test.)

```swift
throw Abort(.conflict, reason: "username '\(data.username)' is not available")
```

* Choose an appropriate `HTTPStatus` code to return from endpoint handlers. The default is always 200 OK on
successful execution, but it can be simply transformed, or wrapped in a custom `Response` if also returning data.

```swift
let createdUserData = CreatedUserData(...) // returns 200 OK
return createdUserData

let response = Response(http: HTTPResponse(status: .created), using: req) // returns 201 Created
try response.content.encode(createdUserData)
return response

return user.delete(on: req).transform(to: .noContent) // returns 204 No Content
```

* In most cases, unless for clarity or the compiler insists, prefer to let Swift infer the type rather than explicitly
specify it. Recent releases of the swift compiler have been getting much better at wending their way through
async twists and turns.

* In most cases, prefer nested indentation to flush-left future chaining.

* When specifying closure result variables, prefer using the multi-line format, enclosing them in parentheses. Taken
together, these last three conventions tend to result in less cluttered, more easily scanned code. 

```swift
// future chaining can help with reasoning about complex nesting
    ...
    return user.save(on: req)
}.flatMap(to: UserProfile.self) { savedUser in
    let profile = UserProfile(...)
    return profile.save(on: req)
}.map(to: CreatedUserData.self) { savedProfile in
    let createdUserData = CreatedUserData(...)
    return createdUserData
}

// but nesting is generally going to cause less eye fatigue
return user.save(on: req).flatMap {
    (savedUser) in
    let profile = UserProfile(...)
    return profile.save(on: req).map {
        (savedProfile) in
        let createdUserData = CreatedUserData(...)
        return createdUserData
    }
}
```

And a couple of final random topics:

---
The `docs/` are generated using [`jazzy`](https://github.com/realm/jazzy), with the `.jazzy.yaml` configuration
file included in this repository. They are updated at minimum upon every tagged point release, but should usually
be tracking the master branch. To regenerate them:

```shell
cd <swiftarr-directory>
jazzy --clean -o ./docs
```
Note: The GitHub links within the generated documentation are hard-coded via the `github_file_prefix`
configuration setting to point to the `master` branch tree. This is fine for `master` merges *only*, and care needs
to be taken for tagged releases.

---

Testing under Linux depends on up-to-date `Tests/LinuxMain.swift`  and
`Tests/AppTests/XCTestManifests.swift` files. We fortunately no longer need to manually maintain an
`allTests` array in each of our `XCTestCase` classes, but these files do need to be manually regenerated
whenever a new test has been added.

```shell
cd <swiftarr-directory>
swift test --generate-linuxmain
```
The updated `LinuxMain.swift` and `XCTestManifests.swift` files should be included in any pull
request that adds a test.
