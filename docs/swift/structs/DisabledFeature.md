**STRUCT**

# `DisabledFeature`

```swift
public struct DisabledFeature: Content
```

A feature that has been turned off by the server. If the `appName` is `all`, the indicated `featureName` is disabled at the API level for 
this feature and all relevant endpoints will return errors. For any other value of appName, the API still works, but the indicated client apps should
not allow the feature to be accessed. The goal is to be able to disable code that is impacting server stability or performance without shutting down
the server entirely or disallowing specific clients entirely. 

Used in `UserNotificationData`.
