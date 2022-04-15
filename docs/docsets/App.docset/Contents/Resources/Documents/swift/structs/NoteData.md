**STRUCT**

# `NoteData`

```swift
public struct NoteData: Content
```

Used to obtain the contents of a `UserNote` for display in a non-profile-viewing context.

Returned by:
* `GET /api/v3/user/notes`
* `GET /api/v3/users/ID/note`
* `POST /api/v3/user/note`

See `UserController.notesHandler(_:)`, `UserController.noteHandler(_:data:)`.
