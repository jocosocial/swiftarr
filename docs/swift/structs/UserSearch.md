**STRUCT**

# `UserSearch`

```swift
public struct UserSearch: Content
```

Used to broad search for a user based on any of their name fields.

Returned by:
* `GET /api/v3/users/match/allnames/STRING`
* `GET /api/v3/client/usersearch`

See `UsersController.matchAllNamesHandler(_:)`, `ClientController.userSearchHandler(_:)`.
