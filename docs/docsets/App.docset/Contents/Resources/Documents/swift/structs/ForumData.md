**STRUCT**

# `ForumData`

```swift
public struct ForumData: Content
```

Used to return the contents of a `Forum`.

Returned by:
* `POST /api/v3/forum/categories/ID/create`
* `GET /api/v3/forum/ID`
* `GET /api/v3/events/ID/forum`

See `ForumController.forumCreateHandler(_:data:)`, `ForumController.forumHandler(_:)`,
`EventController.eventForumHandler(_:)`.
