# A Swiftarr Pitch

### Background

Swiftarr started as a project by @grundoon, as a Swift based Twitarr server using Vapor 3. The project used a Postgres database for storage plus Redis for certain kinds of cached data. After writing most of an API layer, @grundoon put the project on pause. I think he has plans for a different backend, using Redis more aggressively.

I started dinking with the Swiftarr project earlier this year because I was bored. I updated the project to Vapor 4, fleshed out the API layer, and added a web front end. I also made a fork of my Kraken client that works with this new API.

### Why Swiftarr

Okay, here’s the pitch for moving to Swiftarr for 2022:

Swiftarr has a bunch of new features. Many of these were listed in the readme for @grundoon’s repo: https://github.com/grundoon/swiftarr

Here’s a short list of differentiating features:

* Looking For Group feature - A user can create a LFG describing an event they want to have, others can then search for LFGs and join up. LFGs have group chats similar to Seamail chats. 
* Forum Categories - does what you’d think
* Event Forums - All events get an associated Forum created for them.
* Moderator Features - Report views, edit histories, auto-quarantined content, timed user bans, moderator action log, mod-only discussion forum
* User Account Features - Sub-accounts, symmetric user blocks as well as user mutes
* Context-aware search for the web UI. 

There’s a bunch of minor features, from twarrts allowing 4 images to a unified notifications endpoint.

Plus, there’s a bunch of stuff that I still want to do for 2022:

* Board Games and Karaoke song indexes would tie into LFGs, with a “find people to play this” button of some sort.
* Canonical links for most content, including twarrts and forum posts. This means, with some work, a native client could scan a forum post’s text, find a link to a LFG, and make that link open in-app.
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