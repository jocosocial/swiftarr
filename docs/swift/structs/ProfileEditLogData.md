**STRUCT**

# `ProfileEditLogData`

```swift
public struct ProfileEditLogData: Content
```

Used to return data moderators need to view previous edits a user made to their profile. 
This structure will have either the `profileData` or `profileImage` field populated.
An array of these stucts is placed inside `ProfileModerationData`.
