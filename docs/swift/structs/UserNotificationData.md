**STRUCT**

# `UserNotificationData`

```swift
public struct UserNotificationData: Content
```

Provides updates about server global state and the logged in user's notifications. 
`userNotificationHandler()` is intended to be called frequently by clients (I mean, don't call it once a second).

Returned by AlertController.userNotificationHandler()
