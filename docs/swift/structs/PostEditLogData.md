**STRUCT**

# `PostEditLogData`

```swift
public struct PostEditLogData: Content
```

Used to return a `TwarrtEdit` or `ForumPost`'s data for moderators. The two models use the same data structure, as all the fields happen to be the same.

Included in:
* `ForumPostModerationData`
* `TwarrtModerationData`

Returned by:
* `GET /api/v3/mod/twarrt/id`
