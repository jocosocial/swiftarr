**EXTENSION**

# `Size`
```swift
extension Size
```

## Properties
### `zero`

```swift
public static let zero = Size(width: 0, height: 0)
```

Size whose width and height are both zero.

## Methods
### `init(width:height:)`

```swift
public init(width: Int32, height: Int32)
```

Creates a size with specified dimensions.

- Parameters:
  - width: The width value of the size
  - height: The height value of the size

#### Parameters

| Name | Description |
| ---- | ----------- |
| width | The width value of the size |
| height | The height value of the size |

### `<(_:_:)`

```swift
public static func < (lhs: Size, rhs: Size) -> Bool
```

Returns a Boolean value indicating whether the value of the first
argument is less than that of the second argument.

This function is the only requirement of the `Comparable` protocol. The
remainder of the relational operator functions are implemented by the
standard library for any type that conforms to `Comparable`.

- Parameters:
  - lhs: A value to compare.
  - rhs: Another value to compare.

#### Parameters

| Name | Description |
| ---- | ----------- |
| lhs | A value to compare. |
| rhs | Another value to compare. |

### `==(_:_:)`

```swift
public static func == (lhs: Size, rhs: Size) -> Bool
```

Returns a Boolean value indicating whether two values are equal.

Equality is the inverse of inequality. For any values `a` and `b`,
`a == b` implies that `a != b` is `false`.

- Parameters:
  - lhs: A value to compare.
  - rhs: Another value to compare.

#### Parameters

| Name | Description |
| ---- | ----------- |
| lhs | A value to compare. |
| rhs | Another value to compare. |