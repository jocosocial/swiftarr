**STRUCT**

# `ReportData`

```swift
public struct ReportData: Content
```

Used to submit a message with a `Report`.

Required by:
* `POST /api/v3/users/ID/report`
* `POST /api/v3/forum/ID/report`
* `POST /api/v3/forun/post/ID/report`

See `UsersController.reportHandler(_:data:)`, `ForumController.forumReportHandler(_:data:)`
`ForumController.postReportHandler(_:data:)`.
