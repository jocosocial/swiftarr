**STRUCT**

# `SettingsUpdateData`

```swift
public struct SettingsUpdateData: Content
```

Used to update the `Settings` values. Doesn't update everything--some values aren't meant to be updated live. The updated values are saved so
that they'll persist through app launches. Any optional values set to nil are not used to update Settings values.

Required by: `POST /api/v3/events/update`

See `EventController.eventsUpdateHandler(_:data:)`.
