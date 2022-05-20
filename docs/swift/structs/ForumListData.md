**STRUCT**

# `ForumListData`

```swift
public struct ForumListData: Content
```

Used to return the ID, title and status of a `Forum`.

Returned by:
* `GET /api/v3/forum/categories/ID`
* `GET /api/v3/forum/owner`
* `GET /api/v3/user/forums`
* `GET /api/v3/forum/favorites`

See `ForumController.categoryForumsHandler(_:)`, `ForumController.ownerHandler(_:)`,
`ForumController.forumMatchHandler(_:)`, `ForumController.favoritesHandler(_:).
