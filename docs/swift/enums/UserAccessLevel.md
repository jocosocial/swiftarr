**ENUM**

# `UserAccessLevel`

```swift
public enum UserAccessLevel: String, Codable
```

All API endpoints are protected by a minimum user access level.
This `enum` structure MUST match the values in `CreateCustomEnums` in SchemaCreation.swift
as this enum is part of the database schema. This enum is also sent out in several Data Transfer Object types.
Think very carefully about modifying these values.

## Cases
### `unverified`

```swift
case unverified
```

A user account that has not yet been activated. [read-only, limited]

### `banned`

```swift
case banned
```

A user account that has been banned. [cannot log in]

### `quarantined`

```swift
case quarantined
```

A `.verified` user account that has triggered Moderator review. [read-only]

### `verified`

```swift
case verified
```

A user account that has been activated for full read-write access.

### `client`

```swift
case client
```

A special class of account for registered API clients. [see `ClientController`]

### `moderator`

```swift
case moderator
```

An account whose owner is part of the Moderator Team.

### `twitarrteam`

```swift
case twitarrteam
```

Twitarr devs should have their accounts elevated to this level to help handle seamail to 'twitarrteam'

### `tho`

```swift
case tho
```

An account officially associated with Management, has access to all `.moderator`
and a subset of `.admin` functions (the non-destructive ones). Can ban users.

### `admin`

```swift
case admin
```

An Administrator account, unrestricted access.
