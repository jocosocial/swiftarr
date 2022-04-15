**STRUCT**

# `SettingsAdminData`

```swift
public struct SettingsAdminData: Content
```

Used to return the current `Settings` values. Doesn't update everything--some values aren't meant to be updated live, and others are 

Required by: `POST /api/v3/events/update`

See `EventController.eventsUpdateHandler(_:data:)`.
