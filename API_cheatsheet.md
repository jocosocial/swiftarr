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
| T | `POST` | `/api/v3/user/add` | `UserAddData` -> `AddedUserData` | create sub-account |
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
| T | `GET` | `/api/v3/user/alertwords` | -> `AlertKeywordData` | retrieve "Alert Keywords" barrel |
| T | `POST` | `/api/v3/user/alertwords/add/STRING` | -> `AlertKeywordData` | add word to "Alert Keywords" barrel |
| T | `POST` | `/api/v3/user/alertwords/remove/STRING` | -> `AlertKeywordData` | remove word from "Alert Keywords" barrel |
| T | `POST` | `/api/v3/user/barrel` | `BarrelCreateData` -> `BarrelData` | create barrel |
| T | `GET` | `/api/v3/user/barrels` | -> `[BarrelListData]` | retrieve list of all barrels |
| T | `GET` | `/api/v3/user/barrels/seamonkey` | -> `[BarrelListData]` | retrieve list of user's seamonkey barrels |
| T | `GET` | `/api/v3/user/barrels/ID` | -> `BarrelData` | retrieve barrel |
| T | `POST` | `/api/v3/user/barrels/ID/add/STRING` | -> `BarrelData` | add item to barrel |
| T | `POST` | `/api/v3/user/barrels/ID/delete` | -> HTTP Status | delete barrel |
| T | `POST` | `/api/v3/user/barrels/ID/rename/STRING` | -> `BarrelData` | rename barrel |
| T | `POST` | `/api/v3/user/barrels/ID/remove/STRING` | -> `BarrelData` | remove item from barrel |
| T | `GET` | `/api/v3/user/blocks` | -> `BlockedUserData` | retrieve "Blocked Users" barrel |
| T | `GET` | `/api/v3/user/mutes` | -> `MutedUserData` | retrieve "Muted Users" barrel |
| T | `GET` | `/api/v3/user/mutewords` | -> `MuteKeywordData` | retrieve "Muted Keywords" barrel |
| T | `POST` | `/api/v3/user/mutewords/add/STRING` | -> `MuteKeywordData` | add word to "Muted Keywords" barrel |
| T | `POST` | `/api/v3/user/mutewords/remove/STRING` | -> `MuteKeywordData` | remove word from "Muted Keywords" barrel |

* [WIP...]

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- | :--- | :--- |
| T | `GET` | `/api/v3/user/forums` | -> `[ForumData]` | retrieve list of forums owned by user |
| T | `GET` | `/api/v3/user/notes` | -> `[NoteData]` | retrieve all user notes |
| T | `POST` | `/api/v3/user/note` | `NoteUpdateData` -> `NoteData` | update user note |
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
| T | `POST` | `/api/v3/users/ID/note` | `NoteCreateData` -> `CreatedNoteData` | create user note |
| T | `GET` | `/api/v3/users/ID/note` | -> `UserNote.Edit` | retrieve user note for edit |
| T | `POST` | `/api/v3/users/ID/note/delete` | -> HTTP Status | delete user note |

* search

||| Endpoint | Requires -> Returns | Use to... |
| :--- | :--- | :--- |:--- | :--- |
| T | `GET` | `/api/v3/users/match/allnames/STRING` | -> `[UserSearch]` | retrieve list of `displayName|username|realName` matches|
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
---

# Forum
---
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



