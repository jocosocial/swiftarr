**CLASS**

# `SwiftarrErrorMiddleware`

```swift
public final class SwiftarrErrorMiddleware: AsyncMiddleware
```

Captures all errors and transforms them into an internal server error HTTP response.

## Methods
### `respond(to:chainingTo:)`

```swift
public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response
```

See `Middleware`.
