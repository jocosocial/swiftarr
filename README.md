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

Testing during development within Xcode is pretty straightforward, but it is critical that the tests also be run under
the Linux environment in which it will run during production.

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


