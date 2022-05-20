**EXTENSION**

# `Rectangle`
```swift
extension Rectangle
```

## Properties
### `zero`

```swift
public static let zero = Rectangle(point: .zero, size: .zero)
```

Rectangle at the origin whose width and height are both zero.

## Methods
### `init(x:y:width:height:)`

```swift
public init(x: Int, y: Int, width: Int, height: Int)
```

Creates a rectangle at specified point and given size.

- Parameters:
  - x: The x-coordinate of the point
  - y: The y-coordinate of the point
  - width: The width value of the size
  - height: The height value of the size

#### Parameters

| Name | Description |
| ---- | ----------- |
| x | The x-coordinate of the point |
| y | The y-coordinate of the point |
| width | The width value of the size |
| height | The height value of the size |

### `init(x:y:width:height:)`

```swift
public init(x: Int32, y: Int32, width: Int32, height: Int32)
```

Creates a rectangle at specified point and given size.

- Parameters:
  - x: The x-coordinate of the point
  - y: The y-coordinate of the point
  - width: The width value of the size
  - height: The height value of the size

#### Parameters

| Name | Description |
| ---- | ----------- |
| x | The x-coordinate of the point |
| y | The y-coordinate of the point |
| width | The width value of the size |
| height | The height value of the size |

### `==(_:_:)`

```swift
public static func == (lhs: Rectangle, rhs: Rectangle) -> Bool
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