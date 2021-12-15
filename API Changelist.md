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
* Added a new ModeratorActionType: `post`. Used when a mod posts as @moderator or @TwittarTeam. Change only affects Mod-level API.
