#### O = Open Access
#### B = (basic) = requires HTTP Basic Authentication
#### S = (shared) = either Basic or Bearer Authentication
#### T = (token) = requires HTTP Bearer Authentication
#### X = (x-swiftarr-user) = requires HTTP Bearer Authentication + `x-swiftarr-user` header
---

# Auth
---

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| B | `POST` | `/api/v3/auth/login` | -> `TokenStringData` | log in |
| T |  `POST` | `/api/v3/auth/logout` | -> HTTP Status | log out |
| O | `POST` | `/api/v3/auth/recovery` | `UserRecoveryData` -> `TokenStringData` | recover lost password |
---

# User
### (data owned *by* the user)
---

* onboarding

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| O | `POST` | `/api/v3/user/create` | `UserCreateData` -> `CreatedUserData` | create account |
| B | `POST` | `/api/v3/user/verify` | `UserVerifyData` -> HTTP Status | activate account |

* general

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `POST` | `/api/v3/user/add` | `UserCreateData` -> `AddedUserData` | create sub-account |
| S | `POST` | `/api/v3/user/image` | `ImageUploadData` -> `UploadedImageData` | upload profile image |
| S | `POST` | `/api/v3/user/image/remove` |  -> HTTP Status | remove profile image |
| T | `POST` | `/api/v3/user/password` | `UserPasswordData` -> HTTP Status | change password |
| S | `GET` | `/api/v3/user/profile` | -> `UserProfile.Edit` | retrieve profile for edit |
| S | `POST` | `/api/v3/user/profile` | `UserProfileData` -> `UserProfile.Edit` | update profile |
| T | `POST` | `/api/v3/user/username` | `UserUsernameData` -> HTTP Status | change username |
| S | `GET` | `/api/v3/user/whoami` | -> `CurrentUserData` | retrieve username, id, login status |

* barrels

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `GET` | `/api/v3/user/alertwords` | -> `AlertKeywordData` | retrieve "Alert Keywords" Barrel |
| T | `POST` | `/api/v3/user/alertwords/add/STRING` | -> `AlertKeywordData` | add word to "Alert Keywords" Barrel |
| T | `POST` | `/api/v3/user/alertwords/remove/STRING` | -> `AlertKeywordData` | remove word from "Alert Keywords" Barrel |
| T | `POST` | `/api/v3/user/barrel` | `BarrelCreateData` -> `BarrelData` | create Barrel |
| T | `GET` | `/api/v3/user/barrels` | -> `[BarrelListData]` | retrieve list of all Barrels |
| T | `GET` | `/api/v3/user/barrels/seamonkey` | -> `[BarrelListData]` | retrieve list of user's seamonkey Barrels |
| T | `GET` | `/api/v3/user/barrels/ID` | -> `BarrelData` | retrieve Barrel |
| T | `POST` | `/api/v3/user/barrels/ID/add/STRING` | -> `BarrelData` | add item to Barrel |
| T | `POST` | `/api/v3/user/barrels/ID/delete` | -> HTTP Status | delete Barrel |
| T | `POST` | `/api/v3/user/barrels/ID/rename/STRING` | -> `BarrelData` | rename Barrel |
| T | `POST` | `/api/v3/user/barrels/ID/remove/STRING` | -> `BarrelData` | remove item from Barrel |
| T | `GET` | `/api/v3/user/blocks` | -> `BlockedUserData` | retrieve "Blocked Users" Barrel |
| T | `GET` | `/api/v3/user/mutes` | -> `MutedUserData` | retrieve "Muted Users" Barrel |
| T | `GET` | `/api/v3/user/mutewords` | -> `MuteKeywordData` | retrieve "Muted Keywords" Barrel |
| T | `POST` | `/api/v3/user/mutewords/add/STRING` | -> `MuteKeywordData` | add word to "Muted Keywords" Barrel |
| T | `POST` | `/api/v3/user/mutewords/remove/STRING` | -> `MuteKeywordData` | remove word from "Muted Keywords" Barrel |

* [WIP...]

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `GET` | `/api/v3/user/forums` | -> `[ForumListData]` | retrieve list of Forums owned by user |
| T | `GET` | `/api/v3/user/notes` | -> `[NoteData]` | retrieve all user's UserNotes |
| T | `POST` | `/api/v3/user/note` | `NoteUpdateData` -> `NoteData` | update UserNote |
---

# Users
### (data involving *other* users)
---

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| S | `GET` | `/api/v3/users/find/STRING` | -> `UserInfo` | retrieve user info by username |
| S | `GET` | `/api/v3/users/ID` | -> `UserInfo` | retrieve user info by id |
| S | `GET` | `/api/v3/users/ID/header` | -> `UserHeader` | retrieve user's header info |
| S | `GET` | `/api/v3/users/ID/profile` | -> `UserProfile.Public` | retrieve user's profile |
---

* blocks & mutes

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `POST` | `/api/v3/users/ID/block` | -> HTTP Status | block user |
| T | `POST` | `/api/v3/users/ID/mute` | -> HTTP Status | mute user |
| T | `POST` | `/api/v3/users/ID/report` | -> HTTP Status | report a user |
| T | `POST` | `/api/v3/users/ID/unblock` | -> HTTP STatus | unblock user |
| T | `POST` | `/api/v3/users/ID/unmute` | -> HTTP Status | unmute user |

* user notes

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- |:--- | :--- |
| T | `POST` | `/api/v3/users/ID/note` | `NoteCreateData` -> `CreatedNoteData` | create UserNote for user |
| T | `GET` | `/api/v3/users/ID/note` | -> `UserNote.Edit` | retrieve UserNote for edit |
| T | `POST` | `/api/v3/users/ID/note/delete` | -> HTTP Status | delete UserNote for user |

* search

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- |:--- | :--- |
| T | `GET` | `/api/v3/users/match/allnames/STRING` | -> `[UserSearch]` | retrieve list of `displayName|username|realName` matches |
| T | `GET` | `/api/v3/users/match/username/STRING` | -> `[String]` | retrieve list of `username` matches only |
---

# Events
---

* all events

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| O | `GET` | `/api/v3/events` | -> `[EventData]` | retrieve all Events |
| O | `GET` | `/api/v3/events/official` | -> `[EventData]` | retrieve all official Events |
| O | `GET` | `/api/v3/events/shadow` | -> `[EventData]` | retrieve all shadow Events |
| O | `GET` | `/api/v3/events/match/STRING` | -> `[EventData]` | retrieve all Events containing string |

* today's events

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| O | `GET` | `/api/v3/events/now` | -> `[EventData]` | retrieve all Events happening now |
| O | `GET` | `/api/v3/events/official/now` | -> `[EventData]` | retrieve official Events happening now |
| O | `GET` | `/api/v3/events/shadow/now` | -> `[EventData]` | retrieve shadow Events happening now |
| O | `GET` | `/api/v3/events/today` | -> `[EventData]` | retrieve all Events for current day |
| O | `GET` | `/api/v3/events/official/today` | -> `[EventData]` | retrieve official Events for current day|
| O | `GET` | `/api/v3/events/shadow/today` | -> `[EventData]` | retrieve shadow Events for current day |

* event forums

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| S | `GET` | `/api/v3/events/ID/forum` | -> `ForumData` | retrieve the Forum for an Event |
---

# Forum
---

* categories & forums

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| S | `GET` | `/api/v3/forum/categories` | -> `[CategoryData]` | retrieve list of Forum categories |
| S | `GET` | `/api/v3/forum/categories/admin` | -> `[CategoryData]` | retrieve list of admin Forum categories |
| S | `GET` | `/api/v3/forum/categories/user` | -> `[CategoryData]` | retrieve list of user Forum categories |
| S | `GET` | `/api/v3/forum/categories/ID` | -> `[ForumListData]` | retrieve list of Forums in Category |
| T | `POST` | `/api/v3/forum/categories/ID/create` | `ForumCreateData` -> `ForumData` | create Forum in Category |
| T | `GET` | `/api/v3/forum/owner` | -> `[ForumListData]` | retrieve list of Forums owned by user |
| S | `GET` | `/api/v3/forum/ID` | -> `ForumData` | retrieve Forum |
| T | `POST` | `/api/v3/forum/ID/lock` | -> HTTP Status | lock a Forum into read-only state|
| T | `POST` | `/api/v3/forum/ID/rename/STRING` | -> HTTP Status | rename a Forum |
| T | `POST` | `/api/v3/forum/ID/report` | `ReportData` -> HTTP Status | report a Forum |
| T | `POST` | `/api/v3/forum/ID/unlock` | -> HTTP Status | unlock a Forum from read-only state |

* forum posts

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `POST` | `/api/v3/forum/ID/create` | `PostCreateData` -> `PostData` | create ForumPost in Forum |
| S | `GET` | `/api/v3/forum/post/ID` | -> `PostDetailData` | retrieve a ForumPost with like details |
| T | `POST` | `/api/v3/forum/post/ID/delete` | -> HTTP Status | delete a ForumPost |
| S | `GET` | `/api/v3/forum/post/ID/forum` | -> `ForumData` | retrieve the Forum of a ForumPost |
| T | `POST` | `/api/v3/forum/post/ID/image` | `ImageUploadData` -> `PostData` | add/replace a ForumPost image |
| T | `POST` | `/api/v3/forum/post/ID/image/remove` | -> `PostData` | remove a ForumPost image |
| T | `POST` | `/api/v3/forum/post/ID/laugh` | -> `PostData` | add laugh to a ForumPost |
| T | `POST` | `/api/v3/forum/post/ID/like` | -> `PostData` | add like to a ForumPost |
| T | `POST` | `/api/v3/forum/post/ID/love` | -> `PostData` | add love to a ForumPost |
| T | `POST` | `/api/v3/forum/post/ID/unreact` | -> `PostData` | remove laugh/like/love from a ForumPost |
| T | `POST` | `/api/v3/forum/post/ID/report` | `ReportData` -> HTTP Status | report a ForumPost |
| T | `POST` | `/api/v3/forum/post/ID/update` | `PostContentData` -> `PostData` | update a ForumPost |

* search

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| S | `GET` | `/api/v3/forum/match/STRING` | -> `[ForumListData]` | retrieve list of Forums matching string |
| S | `GET` | `/api/v3/forum/ID/search/STRING` | -> `[PostData]` | retrieve all ForumPosts containing string in Forum |
| S | `GET` | `/api/v3/forum/post/search/STRING` | -> `[PostData]` | retrieve all ForumPosts containing string |
---

# Twitarr
---
---

# Moderator
---
---

# Admin
---
||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `POST` | `/api/v3/events/update` | `EventsUpdateData` -> `[EventData]` | update the schedule |
---


# Client
---
||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| X | `GET` | `/api/v3/client/user/headers/since/DATE` | -> `[UserHeader]` | retrieve updated headers |
| X | `GET` | `/api/v3/client/user/updates/since/DATE` | -> `[UserInfo]` | retrieve updated users |
| X | `GET` | `/api/v3/client/usersearch` | -> `[UserSearch]` | retrieve all `UserProfile.userSearch` values |



