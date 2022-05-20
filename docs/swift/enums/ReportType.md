**ENUM**

# `ReportType`

```swift
public enum ReportType: String, Codable
```

The type of entity being reported in a `Report`.

## Cases
### `forum`

```swift
case forum
```

An entire `Forum`.

### `forumPost`

```swift
case forumPost
```

An individual `ForumPost`.

### `twarrt`

```swift
case twarrt
```

An individual `Twarrt`.

### `userProfile`

```swift
case userProfile
```

A `User`, although it specifically refers to the user's profile fields.

### `fez`

```swift
case fez
```

a `FriendlyFez`

### `fezPost`

```swift
case fezPost
```

a `FezPost`
