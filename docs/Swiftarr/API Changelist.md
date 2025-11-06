#  Changes to API functions or structures

## Dec 2, 2021

* THO account can now access most Admin endpoints (creating daily themes, uploading schedules, promoting moderators), but not server settings.
* Added `postAsModerator` and `postAsTwitarrTeam` fields to `PostContentData`. When a post is **created** in Twitarr, Forums, or Fezzes,
and the poster is a moderator, and the poster sets one of these options, the post's author will be set to the indicated user instead of the 
actual poster.
* FezPostData had its UUID-valued `authorID` field changed to a `UserHeader` field named `author`.

## Dec 5, 2021

* Added a method to ModerationController to allow for mods to re-categorize forum threads: `POST /api/v3/mod/forum/:forum_ID/setcategory/:category_ID
* Modified `ForumModerationData` to include the categoryID of a forum being moderated.
* Added a new `ModeratorActionType` case called `move` for moderator log entries where mods use their new power.

## Dec 7, 2021

* Added `FezPostModerationData` to ModeratorControllerStructs, allowing moderators to perform mod actions on fez posts.
* Added `categoryID` to ForumEditLogData, a component of ForumModerationData. Changing the category of a forum now creates a log entry;
the entry contains the previous category the forum was in.

## Dec 14, 2021

* Removed `SeaMonkey` struct, changing all API references to it into the very similar `UserHeader` struct instead.
* Added a new ModeratorActionType: `post`. Used when a mod posts as @moderator or @TwitarrTeam. Change only affects Mod-level API.

## Jan 6, 2022

* Added 'twitarrteam' as a new access level. Members of the Twitarr dev team should be elevated to this access level. TwitarrTeam
access is between Moderator and THO; importantly it gives access to the @TwitarrTeam seamail inbox.
* Added a call to promote users to TwittarTeam, callable by THO and above, and a call to promote users to THO, callable by admin.
* The call to downgrade access levels requires THO access to set 'banned' or 'unverified'. Moderator level still required to set
'quarantined' or 'verified'.
* added the '?foruser=' query parameter to several Fez API calls; used by moderators and TwittarTeam members to access their 
respective shared Seamail inboxes. 

## Feb 2, 2022

* Added a "purpose" string to CategoryData. Intent is to give users an idea of what each category is for, to increase likelihood
that various categories will be used and will contain appropriate content. 

## Feb 8, 2022

* Changed "activeAnnouncementCount" in UserNotificationData to "activeAnnouncementIDs". The new value is an array of all the 
announcement IDs that are currently active. activeAnnouncementIDs.count is equal to the old value. This fixes an issue where
it was possible to have a new announcement where clients couldn't detect it.
* Added "suggestedPlayers" to BoardgameData. This value comes from BoardGameGeek's XML API, and is the value from the "bestNumPlayers"
poll that has the highest number of "best" votes. Roughly, this value should be the community's idea of the 'ideal' number of players
for this game.

## Apr 17, 2022

* Added "hideReplies" to the list of query options for "/api/v3/twitarr" 

## Apr 22, 2022

* FezContentData now has createdByModerator and createdByTwitarrTeam fields, allowing mods to create Seamails that appear to be
from the @moderator user and not themselves.

## Apr 30, 2022

* Added "GET /api/v3/forum/recent" to retrieve recently viewed forums for a user.

## Sep 22, 2022

* When getting forum threads in a category, threads may now be sorted by the start time of the associated Event for each thread.
Only applicable for Event categories (Official Events, Shadow Events). Event categories get Event sorting by default.
* CategoryData now has an isEventCategory field. 

## Sep 24, 2022

* Adds a new filter option when getting fez info: "onlynew", which only returns fezzes with new messages.

## Oct 8, 2022

* Added a board game recommendation engine at: "/api/v3/boardgames/recommend". This code uses some values the DB has about games that
aren't currently available through the API.

## Nov 20, 2022

* With the addition of User Roles, there are now 3 Admin endpoints for managing roles (get/add/delete) for THO and above,
and 3 similar endpoints for use by those with the Shutternaut Manager role for managing the Shutternaut role.
* The ForumListData type has 2 new optional fields, only non-null if the Forum Thread is for an Event. One field is the Date
the event starts, the other is the TimeZone the boat will be in when the event starts.

## Jan 29, 2023

* The server settings endpoint at `GET /api/v3/admin/serversettings` is now available to twitarrteam. It was previously unavailable.
* New endpoint for live reloading of the board games seed at `POST /api/v3/boardgames/reload`. Requires admin.
* New endpoint for live reloading of the karaoke seed at `POST /api/v3/karaoke/reload`. Requires admin.
* Forums now support muting (`GET /api/v3/forum/mutes`, `POST/DELETE /api/v3/forum/:ID/mute`, `POST /api/v3/forum/:ID/mute/remove`). A parameter `isMuted` has been added to the various `ForumData` structs reflecting this state.
* Forum sort order is now influenced by the mute state. Muted forums sort to the end of the paginated results.
* Forums associated with a schedule event now contain the event ID.

## Feb 1, 2023

* Added PhonecallController which adds several endpoints supporting phone calls between Twitarr clients. Currently only used by the Kraken.
The new controller includes the addition of several phone-related notification packets which may be sent over the Notification Websockets.
* Added UserFavorite endpoints, to get/add/remove favorites. Used by phonecall UI so user can call favorites without performing a search.
But, this feature may have other users.

## Feb 13, 2023

* The BoardgameData DTO has a new field: "hasExpansions" which is TRUE iff the boardgame is a base game for which there exist expansions
in the game library. This means a game that has published expansions will still return FALSE for this field if the board game library
doesn't have the expansions.

## Feb 19, 2023

* Fezzes now support a `search` parameter. This works just like all of the other searchable endpoints. Seamails and LFGs are now searchable in the API!

## Feb 27, 2023

* Fez `open`, `joined`, and `owned` queries now support a `hidePast` parameter. When `true`, fezzes with a start date more than 1 hour in the past will be hidden. These queries use default values that match query behavior prior to the addition of this parameter, so clients which do not support it will see no change in list behavior.
* Fez `joined` and `owned` queries now allow the `cruiseday` parameter. It functions identically to the `cruiseday` parameter on `open` fezzes.

## Sep 21, 2023
* New AdminController endpoint at `GET /api/v3/admin/schedule/viewlog` to view the automatic schedule update log and at `GET /api/v3/admin/schedule/viewlog/:log_id` for specific log event.
* New AdminController endpoint at `GET /api/v3/admin/schedule/reload` to trigger a run of the automatic schedule update process.

## Dec 15, 2023
* Announcement management endpoints now have minimum access level of `twitarrTeam` rather than `tho`.

## Dec 27, 2023
* Add `timeZoneID` to `EventData` struct.
* Disabled features now return HTTP 451.

## Jan 17, 2024
* THO and Admin accounts can continue to use Swiftarr features even if those sections have been disabled.
* New FezController endpoints to mute/unmute a Fez at `POST/DELETE /api/v3/fez/:fez_ID/mute` and `POST /api/v3/fez/:fez_ID/mute/remove`.
* New ForumController endpoint at `GET /api/v3/forum/unread` to retrieve a list of forums that are unread to the requesting user.
* `ProfilePublicData` now includes `dinnerTeam` field, and no longer includes `preferredPronoun`. Pronouns were moved to `UserHeader`.
* Add `timeZoneID` to `FezData` and `ForumListData`.
* Moderators and above can specify a `creatorid` parameter in the `GET /api/v3/forum/search` request.
* Moderator Action Log now returns a `ModeratorActionLogResponseData` rather than `[ModeratorActionLogData]`.

## Feb 12, 2024
* New ForumController endpoints for retrieving pinned posts (`GET /api/v3/forum/:forumID/pinnedposts`) and pinning/unpinning them (`POST/DELETE /api/v3/forum/post/:postID/pin`).
* New ForumController endpoints for moderators to pin a forum thread at `POST/DELETE /api/v3/forum/ID/pin`.

## Feb 19, 2024
New Micro Karaoke feature. API changes include:
* new Controller Structs (DTOs) only used by Micro Karaoke
* a new field in the Global Notification struct,
* a new App Feature enum case, 
* new notification type,
* new Report types (both Songs and Song Snippets are Reportable content),
* new User Role -- KaraokeAmbassador

## Feb 27, 2024
* `UserNotificationData` now includes `nextJoinedLFGID` and `nextJoinedLFGTime`.
* `SettingsAdminData` now includes `upcomingEventNotificationSeconds`, `upcomingEventNotificationSetting`, and `upcomingLFGNotificationSetting`.
* New `SocketNotificationType` of `joinedLFGStarting`.

## Jun 25, 2024
* `PostSearchData` now uses `Paginator` to report pagination data--previously the same data was reported via top-level ints.

## Jun 28, 2024
* `BoardgameData` has new fields: gameTypes, categories, and mechanics.
* `BoardgameResponseData` now uses a standard paginator instead of top-level total, start, and limit fields.
* `/api/v3/boardgames/expansions/:boardgameID` now returns a `BoardgameResponseData` instead of an array of `BoardgameData`

## Aug 19, 2024
* Bunch of new APIs in the new PerformerController, along with associated DTOs. All additive.
* `EventData` now has a list of the Performers that will be at the event.
* New App feature for Performer methods.

## Aug 22, 2024
* Add `PersonalEvent` feature.
* API endpoints, notification and report types, DTO.
* Add `isFavorite` to `ProfilePublicData`

## Dec 3, 2024
* UserNotificationData has new fields for `addedTo<Seamail, LFG, PrivateEvent>`. Although these are additive, since they take precedence
over their "newMessageCount" analogues, some cases where previously clients would see a message count field increase, now they see the
associated AddedToChat field value increase.
* UserNotificationData has a new `PrivateEventMessageCount` field
* SocketNotificationData has new `addedTo...` message types

## Dec 25, 2024
* `CategoryData` now implements `Paginator`, removes `numThreads`

## Jan 01, 2025
* New admin endpoint `POST /api/v3/admin/notifications/reload` to trigger the Redis consistency checker.

## Jan 03, 2025
* `/api/v3/boardgames/recommend` is now a `POST` rather than a `GET` with the same request body.

## Feb 13, 2025
* `/api/v3/user/whoami` now includes `accessLevel` and `roles` for the current user

## Feb 15, 2025
* Added new `Performer` delete endpoint `DELETE /api/v3/performer/:performer_ID` (for moderators)

## Nov 05, 2025
* Added `discordUsername` to `ProfilePublicData`.
