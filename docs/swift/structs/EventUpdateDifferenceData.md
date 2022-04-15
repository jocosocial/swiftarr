**STRUCT**

# `EventUpdateDifferenceData`

```swift
public struct EventUpdateDifferenceData: Content
```

Used to validate changes to the `Event` database. This public struct shows the differrences between the current schedule and the 
(already uploaded but not processed) updated schedule. Event identity is based on the `uid` field--two events with the same
`uid` are the same event, and if they show different times, we conclude the event's time changed. Two events with different `uid`s
are different events, even if all other fields are exactly the same.

Events that are added or deleted will only appear in deleted or created event arrays. Modified events could appear in any or all of the 3 modification arrays.
Deleted events take their contents from the database. All other arrays take content from the update.

Required by: `POST /api/v3/admin/schedule/verify`

See `EventController.eventsUpdateHandler(_:data:)`.
