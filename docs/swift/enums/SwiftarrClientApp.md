**ENUM**

# `SwiftarrClientApp`

```swift
public enum SwiftarrClientApp: String, Content, CaseIterable
```

Names of clients that consume the Swiftarr client API. Used in the `SettingsAppFeaturePair` struct.
Clients: Be sure to anticipate server values not listed here.

## Cases
### `swiftarr`

```swift
case swiftarr
```

The website, but NOT the API layer

### `cruisemonkey`

```swift
case cruisemonkey
```

Client apps that consume the Swiftarr API

### `rainbowmonkey`

```swift
case rainbowmonkey
```

### `kraken`

```swift
case kraken
```

### `all`

```swift
case all
```

A feature disabled for `all` will be turned off at the API layer , meaning that calls to that area of the API will return errors. Clients should still attempt
to use disabledFeatures to indicate the cause, rather than just displaying HTTP status errors.

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
