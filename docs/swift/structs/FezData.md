**STRUCT**

# `FezData`

```swift
public struct FezData: Content, ResponseEncodable
```

Used to return a `FriendlyFez`'s data.

Returned by these methods, with `members` set to nil.
* `POST /api/v3/fez/ID/join`
* `POST /api/v3/fez/ID/unjoin`
* `GET /api/v3/fez/joined`
* `GET /api/v3/fez/open`
* `GET /api/v3/fez/owner`
* `POST /api/v3/fez/ID/user/ID/add`
* `POST /api/v3/fez/ID/user/ID/remove`
* `POST /api/v3/fez/ID/cancel`

Returned by these  methods, with `members` populated.
* `GET /api/v3/fez/ID`
* `POST /api/v3/fez/create`
* `POST /api/v3/fez/ID/post`
* `POST /api/v3/fex/ID/post/ID/delete`
See `FezController.createHandler(_:data:)`, `FezController.joinHandler(_:)`,
`FezController.unjoinHandler(_:)`, `FezController.joinedHandler(_:)`
`FezController.openhandler(_:)`, `FezController.ownerHandler(_:)`,
`FezController.userAddHandler(_:)`, `FezController.userRemoveHandler(_:)`,
`FezController.cancelHandler(_:)`.
