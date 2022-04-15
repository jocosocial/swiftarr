**CLASS**

# `ValidatingDecoder`

```swift
final public class ValidatingDecoder: Decoder
```

## Properties
### `codingPath`

```swift
public var codingPath: [CodingKey]
```

### `userInfo`

```swift
public var userInfo: [CodingUserInfoKey: Any]
```

## Methods
### `init(with:)`

```swift
public init(with decoder: Decoder) throws
```

### `container(keyedBy:)`

```swift
public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| type | The key type to use for the container. |

### `singleValueContainer()`

```swift
public func singleValueContainer() throws -> SingleValueDecodingContainer
```

### `unkeyedContainer()`

```swift
public func unkeyedContainer() throws -> UnkeyedDecodingContainer
```
