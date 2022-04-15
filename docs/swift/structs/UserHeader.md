**STRUCT**

# `UserHeader`

```swift
public struct UserHeader: Content
```

Used to obtain a user's current header information (name and image) for attributed content.

Returned by:
* `GET /api/v3/users/ID/header`
* `GET /api/v3/client/user/headers/since/DATE`

See `UsersController.headerHandler(_:)`, `ClientController.userHeadersHandler(_:)`.
