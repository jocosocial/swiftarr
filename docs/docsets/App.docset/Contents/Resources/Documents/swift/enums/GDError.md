**ENUM**

# `GDError`

```swift
public enum GDError: Swift.Error
```

Represents errors that can be thrown within the SwiftGD module.

- invalidFormat: Image raster format mismatch on import/export
- invalidImage: Contains the reason this error was thrown.
- invalidColor: Contains the reason this error was thrown.
- invalidMaxColors: Asserts sane values for creating indexed Images

## Cases
### `invalidFormat`

```swift
case invalidFormat
```

### `invalidImage(reason:)`

```swift
case invalidImage(reason: String)
```

### `invalidColor(reason:)`

```swift
case invalidColor(reason: String)
```

### `invalidMaxColors(reason:)`

```swift
case invalidMaxColors(reason: String)
```
