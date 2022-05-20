**STRUCT**

# `NoteCreateData`

```swift
public struct NoteCreateData: Content
```

Used to create a `UserNote` when viewing a user's profile. Also used to create a Karaoke song log entry.

Required by: 
* `/api/v3/users/:userID/note`
* `/api/v3/karaoke/:songID/logperformance`

See `UsersController.noteCreateHandler(_:data:)`.
