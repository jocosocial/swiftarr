API
===

Pitch
-----
### Background

Swiftarr started as a project by @grundoon, as a Swift based Twitarr server using Vapor 3. The project used a Postgres database for storage plus Redis for certain kinds of cached data. After writing most of an API layer, @grundoon put the project on pause. I think he has plans for a different backend, using Redis more aggressively.

I started dinking with the Swiftarr project earlier this year because I was bored. I updated the project to Vapor 4, fleshed out the API layer, and added a web front end. I also made a fork of my Kraken client that works with this new API.

### Why Swiftarr

Okay, here’s the pitch for moving to Swiftarr for 2022:

Swiftarr has a bunch of new features. Many of these were listed in the readme for @grundoon’s repo: https://github.com/grundoon/swiftarr

Here’s a short list of differentiating features:

* Friendly Fez - A Looking For Group feature. A user can create a Fez describing an event they want to have, others can then search for Fezzes and join up. Fezzes have group chats similar to Seamail chats. 
* Forum Categories - does what you’d think
* Event Forums - All events get an associated Forum created for them.
* Moderator Features - Report views, edit histories, auto-quarantined content, timed user bans, moderator action log, mod-only discussion forum
* User Account Features - Sub-accounts, symmetric user blocks as well as user mutes
* Context-aware search for the web UI. 

There’s a bunch of minor features, from twarrts allowing 4 images to a unified notifications endpoint.

Plus, there’s a bunch of stuff that I still want to do for 2022:

* Board Games and Karaoke song indexes would tie into Friendly Fez, with a “find people to play this” button of some sort.
* Canonical links for most content, including twarrts and forum posts. This means, with some work, a native client could scan a forum post’s text, find a link to a Fez, and make that link open in-app.
* Come up with a plan for DB migration, allowing us to deploy the server via Heroku or similar before boat, and migrate the DB to the boat server on embarkation day.

### Why Not Swiftarr

It’s not done. I had been hoping to get a stable API layer and a mostly-complete web front end by Sept 1, to give client devs time to update apps to the new APIs. I’m not too far off from that goal, but API changes are still happening and the web front end is not feature-complete.

Currently missing from the API:

* A hashtag endpoint, like V2 has. We currently scan user content for @mentions as it is POSTed, which increments mention counts delivered to mentioned users the next time they hit the notification endpoint. We should also scan for #hashtags, store into a tag-frequency table, and add an endpoint that provides hashtag completions.

Missing from the web UI:

* User profiles need work.
* Users can't set mutewords.

Generally missing stuff:

* Documentation needs to be regenerated. Also updated. Also we need more of it.
* Tests are out of date. I’m not a TDD type, but do believe in building a test suite for stable code.
* I’d like to enable HTTPS. I mean, I’d really like to require HTTPS, but I don’t know enough about the boat’s network environment to be sure this can be done.

Swiftarr also does a few things differently than V2. Much of this difference is driven by blocks. When user A blocks user B, all content by any of A’s accounts is hidden from each of B’s accounts, and all of B’s content is likewise hidden from each of A’s accounts. B won’t even know they’re blocked. Because of this, user-created content is not accessible when not logged in (otherwise B could just log out and spy on A’s content). Also, user accounts are canonically identified by ID, not username. A user can change their username, leading to degenerate cases where somebody’s @mention starts referring to a different account.

### Timeline

We're currently about 7 months before boat; I'm pretty sure I can get the server code polished for deployment in that time. Client devs need time to migrate their code to the new V3 APIs; I was hoping to be able to promise API stability by Sept 1, but can promise a mostly stable API by that date. So, were we to decide to adopt this codebase, I believe client devs could start work updating their code at that time, knowing that there may be minor API changes to come.

Following that, I'd estimate we'd have a beta in January, v1.0 deployment code loaded onto the Twitarr server just before it gets installed on the boat, and a mad rush to fix a nasty bug just before everything goes live on embarkation day. The usual.

Anyway, the next step is to figure out whether we want to adopt this code, adopt somebody's else's code, or stick with V2 for 2022. I'd like to have that bit figured out within the next 3 weeks or so.

APIv3 Welcome
-------------

* Users
    - can create multiple sub-accounts, all tied to one registration code
    - can change username
    - can create unlimited lists of other users 
* Authentication
    - all authentication is done through HTTP headers
    - password recovery uses a a per-user (covers all sub-accounts) recovery key generated when the primary user
account is created (the key is 3 words, nothing cryptic)
* Filtering and Notifying
    - a user can block other users (applies to all sub-accounts) throughout the platform
    - each individual account can mute public content based on individual account or keyword
    - users can add alertwords, and be notified when anyone creates public content containing those words
* Clients
    - are a new class of account permitted to request certain bulk data
    - are static across all client instances (e.g. RainbowMonkey is a client and all instances use a hard-coded username/password)
    - proxy for the actual client user via an `x-swiftarr-user` header, so that blocks are respected
* Barrels
    - are multi-purpose containers which can hold an array of IDs and/or a dictionary of strings
    - are used for block/mute/keyword lists, user-created lists, things not yet thought of
    - a user's set of barrels can be used for filtering or as "auto-complete" results
* Forums
    - all forums belong to a category
    - a category can be restricted ("official") or not (users can create forums therein)
    - categories are created, and forums may be re-categorized, by Moderators
    - forum posts can be reacted to with the same laugh/like/love options as twitarr twarrts
    - forum posts can be bookmarked (this is private to the bookmarking user)
    - forum posts can filtered by boomarks, liked posts
    - get notified when your name is @mentioned in a post, or when an alertword is posted
* Events
    - each event on the schedule can have an "official" associated forum
    - 'follow' events you want to attend, then filter on followed events to see your own personal schedule
    - download individual events as .ics files for import into calendar apps
* Twitarr
    - twarrts can be bookmarked (this is private to the bookmarking user)
    - can be filtered by a user's barrels (lists of users), bookmarks, liked twarrts
    - get notified when your name is @mentioned, or when someone posts a twarrt containing an alertword
* Looking For Group
    - users can create Looking For Group requests for... gaming, dining companions, meetups, activities, anything?
    - LFGs can have a maximum capacity, with a waiting list, or an open-ended number of participants
    - an LFG can have specific start and/or end times, or can be "TBD"
    - LFGs have their own discussion thread
    - LFGs respect user blocks for the creator, posts respect both blocks and mutes
* Games
	- List of all the games in the JoCo Games Library, with descriptions, avg. playtime, and number of players.
	- Create an LFG to play a board game right from the games list.
* More
    - soon™

Client Notes
------------
* Dates are UTC and relative to epoch.
* All authentication is done through HTTP headers. See `AuthController`.
* All entities are referenced by ID (either UUID or Int). While usernames are unlikely to change often, they should be
considered ephemeral and only ever be used to *attempt* to obtain an ID  (`api/v3/users/find/username`).
* Required HTTP payload structs can be encoded as either JSON or MultiPart.
* Returned data is always JSON.
* The intended on-boarding flow:
    1. "welcome!"
    2. username/password ---> recovery key
    3. the user is **strongly** encouraged to screenshot/notes app/write down recovery key before proceeding
    4. "user can now edit profile, read twitarr or forums – if they want to *create* content and Agree to Stuff" then...
    5. registration code --- Basic auth ---> token (user is now logged in)
    6. use token in Bearer auth until token no longer works
* When a token no longer works (401 error response):
    1. try `POST /api/v3/auth/login` with Basic auth
    2. either a new token or a 401 or 403  error is returned
    3. if 401, client is not supplying correct credentials, have user re-enter manually or try recovery
    4. if 403, stop, do not try again, user is read-only    
* more
* soon™

Changelist
----------

### Dec 2, 2021

* THO account can now access most Admin endpoints (creating daily themes, uploading schedules, promoting moderators), but not server settings.
* Added `postAsModerator` and `postAsTwitarrTeam` fields to `PostContentData`. When a post is **created** in Twitarr, Forums, or Fezzes,
and the poster is a moderator, and the poster sets one of these options, the post's author will be set to the indicated user instead of the 
actual poster.
* FezPostData had its UUID-valued `authorID` field changed to a `UserHeader` field named `author`.

### Dec 5, 2021

* Added a method to ModerationController to allow for mods to re-categorize forum threads: `POST /api/v3/mod/forum/:forum_ID/setcategory/:category_ID
* Modified `ForumModerationData` to include the categoryID of a forum being moderated.
* Added a new `ModeratorActionType` case called `move` for moderator log entries where mods use their new power.

### Dec 7, 2021

* Added `FezPostModerationData` to ModeratorControllerStructs, allowing moderators to perform mod actions on fez posts.
* Added `categoryID` to ForumEditLogData, a component of ForumModerationData. Changing the category of a forum now creates a log entry;
the entry contains the previous category the forum was in.

### Dec 14, 2021

* Removed `SeaMonkey` struct, changing all API references to it into the very similar `UserHeader` struct instead.
* Added a new ModeratorActionType: `post`. Used when a mod posts as @moderator or @TwitarrTeam. Change only affects Mod-level API.

### Jan 6, 2022

* Added 'twitarrteam' as a new access level. Members of the Twitarr dev team should be elevated to this access level. TwitarrTeam
access is between Moderator and THO; importantly it gives access to the @TwitarrTeam seamail inbox.
* Added a call to promote users to TwittarTeam, callable by THO and above, and a call to promote users to THO, callable by admin.
* The call to downgrade access levels requires THO access to set 'banned' or 'unverified'. Moderator level still required to set
'quarantined' or 'verified'.
* added the '?foruser=' query parameter to several Fez API calls; used by moderators and TwittarTeam members to access their 
respective shared Seamail inboxes. 

### Feb 2, 2022

* Added a "purpose" string to CategoryData. Intent is to give users an idea of what each category is for, to increase likelihood
that various categories will be used and will contain appropriate content. 

### Feb 8, 2022

* Changed "activeAnnouncementCount" in UserNotificationData to "activeAnnouncementIDs". The new value is an array of all the 
announcement IDs that are currently active. activeAnnouncementIDs.count is equal to the old value. This fixes an issue where
it was possible to have a new announcement where clients couldn't detect it.
* Added "suggestedPlayers" to BoardgameData. This value comes from BoardGameGeek's XML API, and is the value from the "bestNumPlayers"
poll that has the highest number of "best" votes. Roughly, this value should be the community's idea of the 'ideal' number of players
for this game.

Basics
------
The API is a bunch of HTTP endpoints, all of which start with the `/api/v3` prefix. There are a couple of optional Websocket endpoints for specific purposes. All requests and response bodies are JSON, as are all the Websocket messages. Some endpoints return files or images; those endpoints will have the proper HTTP Media type and will be a simple byte stream.

Most endpoints are REST-like, in that they act like there's a resource there and you use `GET .../resource` to get the resource, `POST .../resource/update` to modify it, and `DELETE .../resource` to delete it. Endpoints that fetch a list of things tend to have a fair number of URL query parameters that filter the list of things are returned. This is to facilitate filter combinations. For example:

`GET /api/v3/twitarr`

returns an array of tweets. With no query params, it returns the 50 most recent tweets from any poster. You may add query parameters to filter the results, like this:

`GET /api/v3/twitarr?hashtag=wangwang&byUsername=thepope&start=50&limit=10`

This request will select only tweets made by user `thepope` that include the hashtag `#wangwang`, put them in an array where item 0 in the array is the most recently posted matching tweet, and then return items 50 through 59 in that array.

If you also add `&before=<tweet_ID>` in the request query, you will get a (mostly) stable result set. Set the before value to the largest tweetID you're aware of (their IDs are numbered sequentially), then make multiple requests with different start and limit values, (but the same value for `before`) and you'll get results that don't drift as new matching tweets are posted.

### Errors

All endpoints return valid HTTPStatus values. Endpoints that create a thing will generally return `201 Created` on success. Deletes usually return `204 No Content`. Most other endpoints return `200 OK` on success. When returning errors, calls will return the appropriate 400/500 level error; except we never return `404 Not Found` when the endpoint itself was valid. That is, if `POST /api/v3/tweet/1003/edit` is a valid endpoint (in Vapor terms, one that resolves to a route handler) but tweet #1003 does not exist, we'll return another 400 level error (usually `401 Bad Request`). This way, a `404 Not Found` error can be assured to mean, "There's no handler registered to respond to that URL path" and never "A handler was found and it ran but the database lookup returned 0 records".

A 400-500 error response may not have any content, but if it does, the content will be a JSON-encoded [ErrorResponse](ErrorResponse). The `reason` field of this response will contain a user-facing description of the error(s) that occurred, and in some cases the fieldErrors field will contain individual errors linked to fields in the JSON request payload. The `reason` field will always contain all errors in one big string, so you only need to parse fieldErrors if you want to attach errors to specific UI elements.

In practice I think it may be only `404 Not Found` errors that have no content; once a response handler runs it should always either produce success or an ErrorResponse failure.

### IDs 

IDs, IDs everywhere. Most objects in Swiftarr are referenced by their ID. IDs are always either a UUID or an Integer. When they're an Integer the'll be monotonically increasing. However, even though Forum Posts use Integer IDs, there's a single number pool for **all** posts in **any** forum. This means that the second post in a forum will have an ID that's greater than the first post, but it may not be the next higher number. You can sort Forum Posts by their ID, and it should be the same as sorting by original post date.

Users are generally referred to by their ID, which is a UUID. A user may change their username, so don't rely on that.

When a route requires an ID as part of the route path, the docs will indicate this as `/api/v3/twitter/:twarrt_id` where `:twarrt_id` is the ID of a twarrt, e.g. `1003`.

### Controllers

A Controller is a group of HTTP endpoints that are related in function. For instance, here's the [Summary](TwitarrControllerSummary) page for the Twitarr Controller. The links from the Summary page go to generated doc pages for each endpoint; unfortunately the auto-generated docs think they're describing the handler *function* instead of the URL endpoint where the function is registered.

### Controller Structs (DTOs)

The docs for each endpoint should provide links to any structured data types they use for either their request or response. You can also browse the structs [here](ControllerStructs). However, the documentation for the structs is really their Swift documentation. For those more used to how Javascript or Python deal with JSON, Swift is one of the languages that let you build structured data types and then serialize the whole structure into JSON. Generally, a Swift struct will become a JSON dictionary where each JSON key matches the field name in the struct.

Many fields in controller structs have types that directly map to JSON elementary value types: String, Bool, Int, Array, Dictionary. For some field types it's pretty clear how the field would get serialized to JSON: UUID-valued fields, for example, get converted into UUID strings and dropped into the JSON that way.

Swift has this whole thing with Optionals, unless you're a Swift coder you don't really care. But, an Optional value could be nil, whereas a non-Optional cannot be nil. Unlike C-style nil **pointers**, any type could be an optional--Swift has optional Booleans (NOT pointers to Booleans) that could be true, false, or nil. Optional values will not be emitted in the JSON if their value is nil. For example, in the UserHeader struct:

```var displayName: String?```

The `?` indicates displayName is an optional. If a user's displayName is nil, the JSON returned in a Response will not contain a key for `displayName`.

This also means that for any JSON you're sending in a Request, you must provide values for any field that isn't marked optional. On the one hand this makes easy to see what fields are required, on the other it tends to make JSON decoding fragile, as a non-optional field the server doesn't even use *must* still be there or else the JSON decoding fails.

Finally you may be aware that Swift has a whole bunch of ways to modify how structs get mapped into JSON and back. Swiftarr's Controller Structs don't use any of these mechanisms in order to keep things clear. I don't want client developers having to check CodingKeys to see what the actual JSON key is for a field name.
