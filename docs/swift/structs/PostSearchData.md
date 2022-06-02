**STRUCT**

# `PostSearchData`

```swift
public struct PostSearchData: Content
```

Used to return info about a search for `ForumPost`s. Like forums, this returns an array of `PostData.`
However, this gives the results of a search for posts across all the forums.

Returned by: `GET /api/v3/forum/post/search`
