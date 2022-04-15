**STRUCT**

# `SettingsAppFeaturePair`

```swift
public struct SettingsAppFeaturePair: Content
```

Used to enable/disable features. A featurePair with name: "kraken" and feature: "schedule" indicates the Schedule feature of the Kraken app.
When the server indicates this app:feature pair is disabled, the client app should not show the feature to users, and should avoid calling API calls
related to that feature. Either the app or feature field could be 'all'.

Used in: `SettingsAdminData`, `SettingsUpdateData`
