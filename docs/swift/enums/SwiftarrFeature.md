**ENUM**

# `SwiftarrFeature`

```swift
public enum SwiftarrFeature: String, Content, CaseIterable
```

Functional areas of the Swiftarr API. Used in the `SettingsAppFeaturePair` struct.
Clients: Be sure to anticipate server values not listed here.

## Cases
### `tweets`

```swift
case tweets
```

### `forums`

```swift
case forums
```

### `seamail`

```swift
case seamail
```

### `schedule`

```swift
case schedule
```

### `friendlyfez`

```swift
case friendlyfez
```

### `karaoke`

```swift
case karaoke
```

### `gameslist`

```swift
case gameslist
```

### `images`

```swift
case images
```

### `users`

```swift
case users
```

### `all`

```swift
case all
```

### `unknown`

```swift
case unknown
```

For clients use. Clients need to be prepared for additional values to be added serverside. Those new values get decoded as 'unknown'.

## Methods
### `init(from:)`

```swift
public init(from decoder: Decoder) throws
```

When creating ourselves from a decoder, return .unknown for cases we're not prepared to handle.
