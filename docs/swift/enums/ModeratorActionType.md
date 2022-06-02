**ENUM**

# `ModeratorActionType`

```swift
public enum ModeratorActionType: String, Codable
```

Describes the type of action a moderator took. This enum is used both in the ModeratorAction Model, and in several Moderation DTOs.
Be careful when modifying this. Not all ModeratorActionTypes are applicable to all ReportTypes.

## Cases
### `post`

```swift
case post
```

The moderator has created a post, but is posting as @moderator or @twitarrTeam. 'Post' could be a twarrt, forum post, or fez post.

### `edit`

```swift
case edit
```

The moderator edited a piece of content owned by somebody else. For `user` content, this means the profile fields (custom avatar images can't be
edited by mods, only deleted).

### `delete`

```swift
case delete
```

The moderator deleted somebody else's content. For `user` content, this means the user photo (users and profile fields can't be deleted).

### `move`

```swift
case move
```

The moderator moved somebody's content to another place. Currently this means they moved a forum to a new category.

### `quarantine`

```swift
case quarantine
```

The moderator has quarantined a user or a piece of content. Quarantined content still exists, but the server replaces the contents with a quarantine message.
A quarantined user can still read content, but cannot post or edit.

### `markReviewed`

```swift
case markReviewed
```

If enough users report on some content (e.g. a twarrt or forum post), that content will get auto-quarantined. A mod can review the content and if it's not in violation
they can set it's modStatus to `markReviewed` to indicate the content is OK. This protects the content from auto-quarantining.

### `lock`

```swift
case lock
```

The moderator has locked a piece of content. Locking prevents the owner from modifying the content; locking a forum or fez prevents new messages
from being posted.

### `unlock`

```swift
case unlock
```

The moderator has unlocked a piece of content.

### `accessLevelUnverified`

```swift
case accessLevelUnverified
```

The mod set the `userAccessLevel` of a user to `.unverified`

### `accessLevelBanned`

```swift
case accessLevelBanned
```

The mod set the `userAccessLevel` of a user to `.banned`

### `accessLevelQuarantined`

```swift
case accessLevelQuarantined
```

The mod set the `userAccessLevel` of a user to `.quarantined`

### `accessLevelVerified`

```swift
case accessLevelVerified
```

The mod set the `userAccessLevel` of a user to `.verified`

### `tempQuarantine`

```swift
case tempQuarantine
```

The mod set a temporary quarantine on the user.

### `tempQuarantineCleared`

```swift
case tempQuarantineCleared
```

The mod cleared a temporary quarantine on the user.
