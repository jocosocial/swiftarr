**STRUCT**

# `Request.UserCache`

```swift
public struct UserCache
```

## Methods
### `getUser(_:)`

```swift
public func getUser(_ userUUID: UUID) -> UserCacheData?
```

### `getUser(username:)`

```swift
public func getUser(username: String) -> UserCacheData?
```

### `getUser(token:)`

```swift
public func getUser(token: String) -> UserCacheData?
```

### `updateUser(_:)`

```swift
public func updateUser(_ userUUID: UUID) async throws -> UserCacheData
```

### `updateUsers(_:)`

```swift
public func updateUsers(_ uuids: [UUID]) async throws
```
