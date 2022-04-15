**ENUM**

# `FezType`

```swift
public enum FezType: String, CaseIterable, Codable
```

The type of `FriendlyFez`.

## Cases
### `closed`

```swift
case closed
```

A closed chat. Participants are set at creation and can't be changed. No location, start/end time, or capacity.

### `activity`

```swift
case activity
```

Some type of activity.

### `dining`

```swift
case dining
```

A dining LFG.

### `gaming`

```swift
case gaming
```

A gaming LFG.

### `meetup`

```swift
case meetup
```

A general meetup.

### `music`

```swift
case music
```

A music-related LFG.

### `other`

```swift
case other
```

Some other type of LFG.

### `shore`

```swift
case shore
```

A shore excursion LFG.
