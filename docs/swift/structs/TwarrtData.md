**STRUCT**

# `TwarrtData`

```swift
public struct TwarrtData: Content
```

Used to return a `Twarrt`'s data.

Returned by:
* `POST /api/v3/twitarr/create`
* `POST /api/v3/twitarr/ID/update`
* `POST /api/v3/twitarr/ID/image`
* `POST /api/v3/twitarr/ID/image/remove`
* `POST /api/v3/twitarr/ID/laugh`
* `POST /api/v3/twitarr/ID/like`
* `POST /api/v3/twitarr/ID/love`
* `POST /api/v3/twitarr/ID/unreact`
* `POST /api/v3/twitarr/ID/reply`
* `GET /api/v3/twitarr/bookmarks`
* `GET /api/v3/twitarr/likes`
* `GET /api/v3/twitarr/mentions`
* `GET /api/v3/twitarr/`
* `GET /api/v3/twitarr/barrel/ID`
* `GET /api/v3/twitarr/hashtag/#STRING`
* `GET /api/v3/twitarr/search/STRING`
* `GET /api/v3/twitarr/user`
* `GET /api/v3/twitarr/user/ID`

See `TwitarrController.twarrtCreateHandler(_:data:)`, `TwitarrController.twarrtUpdateHandler(_:data:)`
`TwitarrController. imageHandler(_:data:)`, `TwitarrController.imageRemoveHandler(_:)`
`TwitarrController.twarrtLaughHandler(_:)`, `TwitarrController.twarrtLikeHandler(_:)`,
`TwitarrController.twarrtLoveHandler(_:)`, `TwitarrController.twarrtUnreactHandler(_:)`,
`TwitarrController.replyHandler(_:data:)`, `TwitarrController.bookmarksHandler(_:)`,
`TwitarrController.likesHandler(_:)`, `TwitarrController.mentionsHandler(_:)`,
`TwitarrController.twarrtsHandler(_:)`, `TwitarrController.twarrtsBarrelHandler(_:)`,
`TwitarrController.twarrtsHashtagHandler(_:)`, `TwitarrController.twarrtsSearchHandler(_:)`,
`TwitarrController.twarrtsUserHandler(_:)`, `TwitarrController.userHandler(_:)`.
