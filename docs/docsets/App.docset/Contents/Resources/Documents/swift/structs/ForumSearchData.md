**STRUCT**

# `ForumSearchData`

```swift
public struct ForumSearchData: Content
```

Used to return a (partial) list of forums along with the number of forums in the found set. Similar to CategoryData, but the 
forums need not be from the same category. Instead, this returns forums that match a common attribute acoss all categores.

Returned by:
* `GET /api/v3/forum/favorites`
* `GET /api/v3/forum/owner`

See `ForumController.categoriesHandler(_:)`
