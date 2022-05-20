**EXTENSION**

# `Bool`
```swift
extension Bool: RESPValueConvertible
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
