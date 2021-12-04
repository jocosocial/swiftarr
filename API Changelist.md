#  Changes to API functions or structures

## Dec 2, 2021

* THO account can now access most Admin endpoints (creating daily themes, uploading schedules, promoting moderators), but not server settings.
* Added `postAsModerator` and `postAsTwitarrTeam` fields to `PostContentData`. When a post is **created** in Twitarr, Forums, or Fezzes,
and the poster is a moderator, and the poster sets one of these options, the post's author will be set to the indicated user instead of the 
actual poster.
* FezPostData had its UUID-valued `authorID` field changed to a `UserHeader` field named `author`.


