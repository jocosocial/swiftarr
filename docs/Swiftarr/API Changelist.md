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
