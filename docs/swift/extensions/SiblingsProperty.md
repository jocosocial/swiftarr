**EXTENSION**

# `SiblingsProperty`
```swift
extension SiblingsProperty
```

## Methods
### `attachOrEdit(from:to:on:_:)`

```swift
public func attachOrEdit(from: From, to: To, on database: Database, _ edit: @escaping (Through) -> () = { _ in }) async throws
```

A thing that it seems like Fluent ought to have, but doesn't. Implemented in-package
this could get rid of the from: parameter, as the property wrapper knows about its object.
Fluent has a very similar attach() method, but it only calls your edit() block if it creates
the pivot.

Anyway, given From and To sibling objects where From needs to be the object that contains
the sibling property, finds or creates the pivot model, calls the edit block so you can mod it,
and saves the pivot. 

Importantly, the edit closure is always called, whether a new pivot is created or not.
