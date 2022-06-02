**STRUCT**

# `Paginator`

```swift
public struct Paginator: Content
```

Composes into other structs to add pagination.

Generally this will be added to a top-level struct along with an array of some result type, like this:

```
	struct SomeCollectionData: Content {
		var paginator: Paginator
		var collection: [CollectionElementType]
	}
```
The Paginator lets you page through results, showing the total number of pages and the current page.
The outer-level struct should document the sort ordering for the returned collection; the first element
in the sorted collection is returned in the first result element when start = 0.

In many cases the size of the returned array will be smaller than limit, and not only at the end of the results.
In several cases the results may be filtered after the database query returns. The next 'page' of results should
be calculated with `start + limit`, not with `start + collection.count`.
