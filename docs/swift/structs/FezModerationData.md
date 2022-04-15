**STRUCT**

# `FezModerationData`

```swift
public struct FezModerationData: Content
```

Used to return data a moderator needs to moderate a fez. 

Returned by:
* `GET /api/v3/mod/fez/:fez_id`

Note that FezPosts can't be edited and don't have an edit log.

See `ModerationController.fezModerationHandler(_:)`
