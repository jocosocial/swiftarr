**STRUCT**

# `AnnouncementData`

```swift
public struct AnnouncementData: Content
```

An announcement to display to all users. 

- Note: Admins can modify Announcements, but should only do so to correct typos or change the displayUntil time. Therefore if a user has seen an announcement,
they need not be notified again if the announcement is edited. Any material change to the content of an announcement should be done via a **new** announcement, 
so that user notifications work correctly.

Returned by:
* `GET /api/v3/notification/announcements`
* `GET /api/v3/notification/announcement/ID` for admins/THO only.
