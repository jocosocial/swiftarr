**STRUCT**

# `KeywordData`

```swift
public struct KeywordData: Content
```

Used to obtain the user's current list of alert or mute keywords.

Returned by:
* `GET /api/v3/user/alertwords`
* `POST /api/v3/user/alertwords/add/STRING`
* `POST /api/v3/user/alertwords/remove/STRING`
* `GET /api/v3/user/mutewords`
* `POST /api/v3/user/mutewords/add/STRING`
* `POST /api/v3/user/mutewords/remove/STRING`

See `UserController.alertwordsHandler(_:)`, `UserController.alertwordsAddHandler(_:)`,
`UserController.alertwordsRemoveHandler(_:)`.
