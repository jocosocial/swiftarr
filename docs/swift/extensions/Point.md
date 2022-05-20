**EXTENSION**

# `Point`
```swift
extension Point
```

## Properties
### `zero`

```swift
public static let zero = Point(x: 0, y: 0)
```

The point at the origin (0,0).

## Methods
### `init(x:y:)`

```swift
public init(x: Int32, y: Int32)
```

Creates a point with specified coordinates.

- Parameters:
  - x: The x-coordinate of the point
  - y: The y-coordinate of the point

#### Parameters

| Name | Description |
| ---- | ----------- |
| x | The x-coordinate of the point |
| y | The y-coordinate of the point |

### `==(_:_:)`

```swift
public static func == (lhs: Point, rhs: Point) -> Bool
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