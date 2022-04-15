**STRUCT**

# `TokenStringData`

```swift
public struct TokenStringData: Content
```

Used to return a token string for use in HTTP Bearer Authentication.

Clients can use the `userID` field  to validate the user that logged in matches the user they *thiought* was logging in.
This guards against a situation where one user changes their username to the previous username value
of another user. A client using `/client/user/updates/since` could end up associating a login with the wrong
`User` because they were matching on `username` instead of `userID`.  That is, a user picks a username and logs in
with their own password. Their client has a (out of date) stored User record, for a different user, that had the same username.

Returned by:
* `POST /api/v3/auth/login`
* `POST /api/v3/auth/recovery`

See `AuthController.loginHandler(_:)` and `AuthController.recoveryHandler(_:data:)`.
