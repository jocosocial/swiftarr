**STRUCT**

# `UserPasswordData`

```swift
public struct UserPasswordData: Content
```

Used to change a user's password. Even when already logged in, users need to provide their current password to set a new password.

Required by: `POST /api/v3/user/password`

See `UserController.passwordHandler(_:data:)`.
