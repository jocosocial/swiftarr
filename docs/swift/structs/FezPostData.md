**STRUCT**

# `FezPostData`

```swift
public struct FezPostData: Content
```

Used to return a `FezPost`'s data.

Returned by:
* `GET /api/v3/fez/ID`
* `POST /api/v3/fez/ID/post`
* `POST /api/v3/fez/ID/post/ID/delete`

See: `FezController.fezHandler(_:)`, `FezController.postAddHandler(_:data:)`,
`FezController.postDeleteHandler(_:)`.
