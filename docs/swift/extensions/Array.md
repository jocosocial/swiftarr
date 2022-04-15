**EXTENSION**

# `Array`
```swift
extension Array where Element: Model
```

## Methods
### `childCountsPerModel(atPath:on:fluentFilter:sqlFilter:)`

```swift
public func childCountsPerModel<ChildModel: Model>(atPath: KeyPath<Element, ChildrenProperty<Element, ChildModel>>, on db: Database,
		fluentFilter: @escaping (QueryBuilder<ChildModel>) -> () = {_ in },
		sqlFilter: ((SQLSelectBuilder) -> ())? = nil)
		async throws -> Dictionary<Element.IDValue, Int>
```

Returns a Dictionary mapping IDs of the array elements to counts of how many associated Children each element has in the database.

Result is a Dictionary instead of an array because (I think?) SQL may coalesce array values with the same ID, resulting in a output array
smaller than the input. Also, SQL won't return rows for UUIDS that aren't in the table.

If the database is SQL-backed, this method uses SQLKit to get counts for the # of related rows of each array element all with one call. 
This is considerably faster than the Fluent-only path, saving ~1.2ms per array element. For a 50 element array, the SQLKit path will take
~2ms, and the Fluent path will take ~75ms.

The filter callbacks are used to modify the Fluent or SQLKit query before it runs. They are given the appropriate type of partially-built query builder.
The intent is that the filters express the same operation (only one will be used for any connected database).
