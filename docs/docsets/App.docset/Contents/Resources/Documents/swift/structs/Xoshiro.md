**STRUCT**

# `Xoshiro`

```swift
public struct Xoshiro: RandomNumberGenerator
```

Random number generator that can be initialized with a seed value.
Copied from https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlRandom.swift

The idea here is that this RNG is seeded with a user's userID, and will always produce the same sequence of numbers when building a user's identicon..

## Methods
### `init(seed:)`

```swift
public init(seed: StateType)
```

### `init(seed:)`

```swift
public init(seed: UUID)
```

### `next()`

```swift
public mutating func next() -> UInt64
```
