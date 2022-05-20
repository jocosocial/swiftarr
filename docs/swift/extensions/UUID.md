**EXTENSION**

# `UUID`
```swift
extension UUID: RESPValueConvertible
```

## Methods
### `init(fromRESP:)`

```swift
public init?(fromRESP value: RESPValue)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The `RESPValue` representation to attempt to initialize from. |

### `convertedToRESPValue()`

```swift
public func convertedToRESPValue() -> RESPValue
```

Creates a `RESPValue` representation of the conforming type's value.
