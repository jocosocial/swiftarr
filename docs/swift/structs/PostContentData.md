**STRUCT**

# `PostContentData`

```swift
public struct PostContentData: Content
```

Used to create or update a `ForumPost`, `Twarrt`, or `FezPost`. 

Required by:
* `POST /api/v3/forum/ID/create`
* `POST /api/v3/forum/post/ID`
* `POST /api/v3/forum/post/ID/update`
* `POST /api/v3/twitarr/create`
* `POST /api/v3/twitarr/ID/reply`
* `POST /api/v3/twitarr/ID/update`
* `POST /api/v3/fez/ID/post`

See `ForumController.postUpdateHandler(_:data:)`.
