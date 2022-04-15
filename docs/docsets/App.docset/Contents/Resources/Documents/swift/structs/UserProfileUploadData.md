**STRUCT**

# `UserProfileUploadData`

```swift
public struct UserProfileUploadData: Content
```

Used to edit the current user's profile contents. For profile data on users, see `ProfilePublicData`.

Required by: 
* `POST /api/v3/user/profile`

Returned by:
* `GET /api/v3/user/profile`
* `POST /api/v3/user/profile`

See `UserController.profileHandler(_:)`, `UserController.profileUpdateHandler(_:data:)`.
