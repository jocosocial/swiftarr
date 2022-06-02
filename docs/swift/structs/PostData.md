**STRUCT**

# `PostData`

```swift
public struct PostData: Content
```

Used to return a `ForumPost`'s data.

Returned by:
* `POST /api/v3/forum/ID/create`
* `POST /api/v3/forum/post/ID/update`
* `POST /api/v3/forum/post/ID/image`
* `POST /api/v3/forum/post/ID/image/remove`
* `GET /api/v3/forum/ID/search/STRING`
* `GET /api/v3/forum/post/search/STRING`
* `POST /api/v3/forum/post/ID/laugh`
* `POST /api/v3/forum/post/ID/like`
* `POST /api/v3/forum/post/ID/love`
* `POST /api/v3/forum/post/ID/unreact`
* `GET /api/v3/forum/bookmarks`
* `GET /api/v3/forum/likes`
* `GET /api/v3/forum/mentions`
* `GET /api/v3/forum/posts`
* `GET /api/v3/forum/post/hashtag/#STRING`

See `ForumController.postCreateHandler(_:data:)`, `ForumController.postUpdateHandler(_:data:)`,
`ForumController.imageHandler(_:data:)`, `ForumController.imageRemoveHandler(_:)`,
`ForumController.forumSearchHandler(_:)`, `ForumController.postSearchHandler(_:)`
`ForumController.postLaughHandler(_:)`, `ForumController.postLikeHandler(_:)`
`ForumController.postLoveHandler(_:)`, `ForumController.postUnreactHandler(_:)`,
`ForumController.bookmarksHandler(_:)`, `ForumCOntroller.likesHandler(_:)`,
`ForumController.mentionsHandler(_:)`, `ForumController.postsHandler(_:)`,
`ForumController.postHashtagHandler(_:)`.
