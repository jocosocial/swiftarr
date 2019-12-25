import Vapor

/// Used to return a newly created sub-account's ID and username.
///
/// Returned by: `POST /api/v3/user/add`
///
/// See `UserController.addHandler(_:data:)`.
struct AddedUserData: Content {
    /// The newly created sub-account's ID.
    let userID: UUID
    /// The newly created sub-account's username.
    let username: String
}

/// Used to obtain the user's current list of alert keywords.
///
/// Returned by:
/// * `GET /api/v3/user/alertwords`
/// * `POST /api/v3/user/alertwords/add/STRING`
/// * `POST /api/v3/user/alertwords/remove/STRING`
///
/// See `UserController.alertwordsHandler(_:)`, `UserController.alertwordsAddHandler(_:)`,
/// `UserController.alertwordsRemoveHandler(_:)`.
struct AlertKeywordData: Content {
    /// The name of the barrel.
    let name: String
    /// The muted keywords.
    var keywords: [String]
}

/// Used to create a new user-owned `.seamonkey` or `.userWords` `Barrel`.
///
/// Required by: `POST /api/v3/user/barrel`
///
/// See `UserController.createBarrelHandler(_:data:)`.
struct BarrelCreateData: Content {
    /// The name of the barrel.
    var name: String
    /// An optional list of model UUIDs.
    var uuidList: [UUID]?
    /// An optional list of strings.
    var stringList: [String]?
}

/// Used to return the contents of a user-owned `.seamonkey` or `.userWords` `Barrel`.
///
/// Returned by:
/// * `POST /api/v3/user/barrel`
/// * `GET /api/v3/user/barrels/ID`
/// * `POST /api/v3/user/barrels/ID/add/STRING`
/// * `POST /api/v3/user/barrels/ID/remove/STRING`
/// * `POST /api/v3/user/barrels/ID/rename/STRING`
///
/// See `UserController.createBarrelHandler(_:data:)`, `UserController.barrelHandler(_:)`,
/// `UserController.barrelAddHandler(_:)`, `UserController.barrelRemoveHandler(_:)`,
/// `UserController.renameBarrelHandler(_:)`.
struct BarrelData: Content {
    /// The barrel's ID.
    let barrelID: UUID
    /// The name of the barrel.
    let name: String
    /// The barrel's `SeaMonkey` contents.
    var seamonkeys: [SeaMonkey]
    /// An optional list of strings.
    var stringList: [String]?
}

/// Used to obtain a list of user-owned `Barrel` names and IDs.
///
/// Returned by:
/// * `GET /api/v3/user/barrels`
/// * `GET /api/v3/user/barrels/seamonkey`
///
/// See `UserController.barrelsHandler(_:)`, `UserController.seamonkeyBarrelsHandler(_:)`.
struct BarrelListData: Content {
    /// The barrel's ID.
    let barrelID: UUID
    /// The name of the barrel.
    let name: String
}

/// Used to obtain the user's list of blocked users.
///
/// Returned by: `GET /api/v3/user/blocks`
///
/// See `UserController.blocksHandler(_:)`.
struct BlockedUserData: Content {
    /// The name of the barrel.
    let name: String
    /// The blocked `User`s.
    var seamonkeys: [SeaMonkey]
}

/// Used to return the ID and title of a `Category`.
///
/// Returned by:
/// * `GET /api/v3/forum/categories`
/// * `GET /api/v3/forum/categories/admin`
/// * `GET /api/v3/forum/categories/user`
///
/// See `ForumController.categoriesHandler(_:)`, `ForumController.categoriesAdminHandler(_:)`,
/// `ForumController.categoriesUserHandler(_:)`.
struct CategoryData: Content {
    /// The ID of the category.
    var categoryID: UUID
    /// The title of the category.
    var title: String
}

/// Used to return a newly created `UserNote` for display or further edit.
///
/// Returned by: `POST /api/v3/users/ID/note`
///
/// See `UsersController.noteCreateHandler(_:data:)`.
struct CreatedNoteData: Content {
    /// The ID of the note.
    var noteID: UUID
    /// The text of the note.
    var note: String
}

/// Used to return a newly created account's ID, username and recovery key.
///
/// Returned by: `POST /api/v3/user/create`
///
/// See `UserController.createHandler(_:data:).`
struct CreatedUserData: Content {
    /// The newly created user's ID.
    let userID: UUID
    /// The newly created user's username.
    let username: String
    /// The newly created user's recoveryKey.
    let recoveryKey: String
}

/// Used to obtain the current user's ID, username and logged-in status.
///
/// Returned by: `GET /api/v3/user/whoami`
///
/// See `UserController.whoamiHandler(_:).`
struct CurrentUserData: Content {
    /// The currrent user's ID.
    let userID: UUID
    /// The current user's username.
    let username: String
    /// Whether the user is currently logged in.
    var isLoggedIn: Bool
}

/// Used to obtain an event's details.
///
/// Returned by:
/// * `GET /api/v3/events`
/// * `GET /api/v3/events/official`
/// * `GET /api/v3/events/shadow`
/// * `GET /api/v3/events/now`
/// * `GET /api/v3/events/official/now`
/// * `GET /api/v3/events/shadow/now`
/// * `GET /api/v3/events/today`
/// * `GET /api/v3/events/official/today`
/// * `GET /api/v3/events/shadow/today`
/// * `GET /api/v3/events/match/STRING`
/// * `GET /api/v3/events/favorites`
///
/// See `EventController.eventsHandler(_:)`, `EventController.officialHandler(_:)`,
/// `EventController.shadowHandler(_:)`, `EventController.eventsNowHandler(_:)`,
/// `EventController.officialNowHandler(_:)`,`EventController.shadowNowHandler(_:)`,
/// `EventController.eventsTodayHandler(_:)`, `EventController.officialTodayHandler(_:)`,
/// `EventController.shadowTodayHandler(_:)`, `EventController.eventsMatchHandler(_:)`
/// `EventController.favoritesHandler(_:)`.
struct EventData: Content {
    /// The event's ID.
    var eventID: UUID
    /// The event's title.
    var title: String
    /// A description of the event.
    var description: String
    /// Starting time of the event
    var startTime: Date
    /// Ending time of the event.
    var endTime: Date
    /// The location of the event.
    var location: String
    /// The event category.
    var eventType: String
    /// The event's associated `Forum`.
    var forum: UUID?
    /// Whether user has favorited event.
    var isFavorite: Bool
}

/// Used to update the `Event` database.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
struct EventsUpdateData: Content {
    /// The `.ics` event schedule file.
    var schedule: String
}

/// Used to create or update a `FriendlyFez`.
///
/// Required by:
/// * `POST /api/v3/fez/create`
/// * `POST /api/v3/fez/ID/update`
///
/// See: `FezController.createHandler(_:data:)`, `FezController.updateHandler(_:data:)`.
struct FezContentData: Content {
    /// The `FezType` .label of the fez.
    var fezType: String
    /// The title for the FriendlyFez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time for the fez, a date as string.
    var startTime: String
    /// The ending time for the fez, a date as string.
    var endTime: String
    /// The location for the fez.
    var location: String
    /// The minimum number of seamonkeys needed for the fez.
    var minCapacity: Int
    /// The maximum number of seamonkeys for the fez.
    var maxCapacity: Int
}

/// Used to return a FriendlyFez `Barrel`'s data.
///
/// Returned by:
/// * `POST /api/v3/fez/create`
/// * `POST /api/v3/fez/ID/join`
/// * `POST /api/v3/fez/ID/unjoin`
/// * `GET /api/v3/fez/joined`
/// * `GET /api/v3/fez/open`
/// * `GET /api/v3/fez/owner`
/// * `POST /api/v3/fez/ID/user/ID/add`
/// * `POST /api/v3/fez/ID/user/ID/remove`
/// * `POST /api/v3/fez/ID/cancel`
///
/// See `FezController.createHandler(_:data:)`, `FezController.joinHandler(_:)`,
/// `FezController.unjoinHandler(_:)`, `FezController.joinedHandler(_:)`
/// `FezController.openhandler(_:)`, `FezController.ownerHandler(_:)`,
/// `FezController.userAddHandler(_:)`, `FezController.userRemoveHandler(_:)`,
/// `FezController.cancelHandler(_:)`.
struct FezData: Content {
    /// The ID of the fez.
    var fezID: UUID
    /// The ID of the fez's owner.
    var ownerID: UUID
    /// The `FezType` .label of the fez.
    var fezType: String
    /// The title of the fez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time of the fez.
    var startTime: String
    /// The ending time of the fez.
    var endTime: String
    /// The location for the fez.
    var location: String
    /// The seamonkeys participating in the fez.
    var seamonkeys: [SeaMonkey]
    /// The seamonkeys on a waiting list for the fez.
    var waitingList: [SeaMonkey]
}

/// Used to return a FriendlyFez `Barrel`'s data with discussion posts.
///
/// Returned by:
/// * `GET /api/v3/fez/ID`
/// * `POST /api/v3/fez/ID/post`
/// * `POST /api/v3/fex/ID/post/ID/delete`
///
/// See `FezController.fezHandler(_:)`, `FezController.postAddHandler(_:data:)`,
/// `FezController.postDeleteHandler(_:)`.
struct FezDetailData: Content {
    /// The ID of the fez.
    var fezID: UUID
    /// The ID of the fez's owner.
    var ownerID: UUID
    /// The `FezType` .label of the fez.
    var fezType: String
    /// The title of the fez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time of the fez.
    var startTime: String
    /// The ending time of the fez.
    var endTime: String
    /// The location for the fez.
    var location: String
    /// The seamonkeys participating in the fez.
    var seamonkeys: [SeaMonkey]
    /// The seamonkeys on a waiting list for the fez.
    var waitingList: [SeaMonkey]
    /// The FezPosts in the fez discussion.
    var posts: [FezPostData]
}

/// Used to return a `FezPost`'s data.
///
/// Returned by:
/// * `GET /api/v3/fez/ID`
/// * `POST /api/v3/fez/ID/post`
/// * `POST /api/v3/fez/ID/post/ID/delete`
///
/// See: `FezController.fezHandler(_:)`, `FezController.postAddHandler(_:data:)`,
/// `FezController.postDeleteHandler(_:)`.
struct FezPostData: Content {
    /// The ID of the fez post.
    var postID: Int
    /// The ID of the fez post's author.
    var authorID: UUID
    /// The text content of the fez post.
    var text: String
    /// The image content of the fez post.
    var image: String
}

/// Used to create a new `Forum`.
///
/// Required by: `POST /api/v3/forum/categories/ID/create`
///
/// See `ForumController.forumCreateHandler(_:data:)`.
struct ForumCreateData: Content {
    /// The forum's title.
    var title: String
    /// The text content of the forum post.
    var text: String
    /// The image content of the forum post.
    var image: Data?
}

/// Used to return the contents of a `Forum`.
///
/// Returned by:
/// * `POST /api/v3/forum/categories/ID/create`
/// * `GET /api/v3/forum/ID`
/// * `GET /api/v3/events/ID/forum`
///
/// See `ForumController.forumCreateHandler(_:data:)`, `ForumController.forumHandler(_:)`,
/// `EventController.eventForumHandler(_:)`.
struct ForumData: Content {
    /// The forum's ID.
    var forumID: UUID
    /// The forum's title
    var title: String
    /// The ID of the forum's creator.
    var creatorID: UUID
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether the user has favorited forum.
    var isFavorite: Bool
    /// The posts in the forum.
    var posts: [PostData]
}

/// Used to return the ID, title and status of a `Forum`.
///
/// Returned by:
/// * `GET /api/v3/forum/categories/ID`
/// * `GET /api/v3/forum/owner`
/// * `GET /api/v3/user/forums`
/// * `GET /api/v3/forum/match/STRING`
/// * `GET /api/v3/forum/favorites`
///
/// See `ForumController.categoryForumsHandler(_:)`, `ForumController.ownerHandler(_:)`,
/// `ForumController.forumMatchHandler(_:)`, `ForumController.favoritesHandler(_:).
struct ForumListData: Content {
    /// The forum's ID.
    var forumID: UUID
    /// The forum's title.
    var title: String
    /// The number of posts in the forum.
    var postCount: Int
    /// Timestamp of most recent post. Needs to be optional because admin forums may be empty.
    var lastPostAt: Date?
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether user has favorited forum.
    var isFavorite: Bool
}

/// Used to upload an image file.
///
/// Required by: `POST /api/v3/user/image`
///
/// See `UserController.imageHandler(_:data)`.
struct ImageUploadData: Content {
    /// The name of the image file.
    var filename: String
    /// The image in `Data` format.
    var image: Data
}

/// Used to obtain the user's current list of keywords for muting public content.
///
/// Returned by:
/// * `GET /api/v3/user/mutewords`
/// * `POST /api/v3/user/mutewords/add/STRING`
/// * `POST /api/v3/user/mutewords/remove/STRING`
///
/// See `UserController.mutewordsHandler(_:)`, `UserController.mutewordsAddHandler(_:)`,
/// `UserController.mutewordsRemoveHandler(_:)`.
struct MuteKeywordData: Content {
    /// The name of the barrel.
    let name: String
    /// The muted keywords.
    var keywords: [String]
}

/// Used to obtain the user's list of muted users.
///
/// Returned by: `GET /api/v3/user/mutes`
///
/// See `UserController.mutesHandler(_:)`.
struct MutedUserData: Content {
    /// The name of the barrel.
    let name: String
    /// The muted `User`s.
    var seamonkeys: [SeaMonkey]
}

/// Used to create a `UserNote` when viewing a user's profile.
///
/// Required by: `/api/v3/users/ID/note`
///
/// See `UsersController.noteCreateHandler(_:data:)`.
struct NoteCreateData: Content {
    /// The text of the note.
    var note: String
}

/// Used to obtain the contents of a `UserNote` for display in a non-profile-viewing context.
///
/// Returned by:
/// * `GET /api/v3/user/notes`
/// * `POST /api/v3/user/note`
///
/// See `UserController.notesHandler(_:)`, `UserController.noteHandler(_:data:)`.
struct NoteData: Content {
    /// The ID of the note.
    let noteID: UUID
    /// Timestamp of the note's creation.
    let createdAt: Date
    /// Timestamp of the note's last update.
    let updatedAt: Date
    /// The ID of the associated profile.
    let profileID: UUID
    /// The .displayName of the profile's user.
    var profileUser: String
    /// The text of the note.
    var note: String
}

/// Used to obtain the contents of a `UserNote` for edit when viewing the associated profile.
///
/// Returned by: `GET /api/v3/users/ID/note`
///
/// See `UsersController.noteHandler(_:)`.
struct NoteEditData: Content {
    /// The note's ID.
    var noteID: UUID
    /// The text of the note.
    var note: String
}

/// Used to update a `UserNote` in a non-profile-viewing context.
///
/// Required by: `POST /api/v3/user/note`
///
/// See `UserController.noteHandler(_:data:)`.
struct NoteUpdateData: Content {
    /// The ID of the note being updated.
    let noteID: UUID
    /// The udated text of the note.
    let note: String
}

/// Used to update a `ForumPost` or `Twarrt`, and as a property of `PostEdit`.
///
/// Required by:
/// * `POST /api/v3/forum/post/ID`
///
/// See `ForumController.postUpdateHandler(_:data:)`.
struct PostContentData: Content {
    /// The text of the forum post.
    var text: String
    /// The filename of an existing image.
    var image: String
}

/// Used to create a `ForumPost` or `Twarrt`.
///
/// Required by:
/// * `POST /api/v3/forum/ID/create`
/// * `POST /api/v3/twitarr/create`
///
/// See `ForumController.postCreateHandler(_:data:)`, `TwitarrController.twarrtCreateHandler(_:data:)`.
struct PostCreateData: Content {
    /// The text of the forum post or twarrt.
    var text: String
    /// An optional image in Data format.
    var imageData: Data?
}

/// Used to return a `ForumPost`'s data.
///
/// Returned by:
/// * `POST /api/v3/forum/ID/create`
/// * `POST /api/v3/forum/post/ID/update`
/// * `POST /api/v3/forum/post/ID/image`
/// * `POST /api/v3/forum/post/ID/image/remove`
/// * `GET /api/v3/forum/ID/search/STRING`
/// * `GET /api/v3/forum/post/search/STRING`
/// * `POST /api/v3/forum/post/ID/laugh`
/// * `POST /api/v3/forum/post/ID/like`
/// * `POST /api/v3/forum/post/ID/love`
/// * `POST /api/v3/forum/post/ID/unreact`
/// * `GET /api/v3/forum/bookmarks`
/// * `GET /api/v3/forum/likes`
/// * `GET /api/v3/forum/mentions`
/// * `GET /api/v3/forum/posts`
/// * `GET /api/v3/forum/post/hashtag/#STRING`
///
/// See `ForumController.postCreateHandler(_:data:)`, `ForumController.postUpdateHandler(_:data:)`,
/// `ForumController.imageHandler(_:data:)`, `ForumController.imageRemoveHandler(_:)`,
/// `ForumController.forumSearchHandler(_:)`, `ForumController.postSearchHandler(_:)`
/// `ForumController.postLaughHandler(_:)`, `ForumController.postLikeHandler(_:)`
/// `ForumController.postLoveHandler(_:)`, `ForumController.postUnreactHandler(_:)`,
/// `ForumController.bookmarksHandler(_:)`, `ForumCOntroller.likesHandler(_:)`,
/// `ForumController.mentionsHandler(_:)`, `ForumController.postsHandler(_:)`,
/// `ForumController.postHashtagHandler(_:)`.
struct PostData: Content {
    /// The ID of the post.
    var postID: Int
    /// The timestamp of the post.
    var createdAt: Date
    /// The ID of the post's author.
    var authorID: UUID
    /// The text of the post.
    var text: String
    /// The filename of the post's optional image.
    var image: String
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the post.
    var userLike: LikeType?
    /// The total number of `LikeType` reactions on the post.
    var likeCount: Int
}

// FIXME: needs bookmark, userLike too?
/// Used to return a `ForumPost`'s data with full user `LikeType` info.
///
/// Returned by: `GET /api/v3/forum/post/ID`
///
/// See `ForumController.postHandler(_:)`.
struct PostDetailData: Content {
    /// The ID of the post.
    var postID: Int
    /// The timestamp of the post.
    var createdAt: Date
    /// The ID of the post's author.
    var authorID: UUID
    /// The text of the forum post.
    var text: String
    /// The filename of the post's optional image.
    var image: String
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The seamonkeys with "laugh" reactions on the post.
    var laughs: [SeaMonkey]
    /// The seamonkeys with "like" reactions on the post.
    var likes: [SeaMonkey]
    /// The seamonkeys with "love" reactions on the post.
    var loves: [SeaMonkey]
}

/// Used to update a user's profile contents.
///
/// Required by: `POST /api/v3/user/profile`
///
/// See `UserController.profileUpdateHandler(_:data:)`.
struct ProfileEditData: Content {
    /// An optional blurb about the user.
    var about: String
    /// An optional name for display alongside the username.
    var displayName: String
    /// An optional email address.
    var email: String
    /// An optional home location (e.g. city).
    var homeLocation: String
    /// An optional greeting/message to visitors of the profile.
    var message: String
    /// An optional preferred form of address.
    var preferredPronoun: String
    /// An optional real name of the user.
    var realName: String
    /// An optional ship cabin number.
    var roomNumber: String
    /// Whether display of the optional fields' data should be limited to logged in users.
    var limitAccess: Bool
}

/// Used to return a user's public profile contents.
///
/// Returned by: `GET /api/v3/users/ID/profile`
///
/// See `UsersController.profileHandler(_:)`.
struct ProfilePublicData: Content {
    /// The profile's ID.
    var profileID: UUID
    /// A generated displayName + username string.
    var displayedName: String
    /// An optional blurb about the user.
    var about: String
    /// An optional email address for the user.
    var email: String
    /// An optional home location for the user.
    var homeLocation: String
    /// An optional greeting/message to visitors of the profile.
    var message: String
    /// An optional preferred pronoun or form of address.
    var preferredPronoun: String
    /// An optional real world name of the user.
    var realName: String
    /// An optional cabin number for the user.
    var roomNumber: String
    /// A UserNote owned by the visiting user, about the profile's user (see `UserNote`).
    var note: String?
}

/// Used to submit a message with a `Report`.
///
/// Required by:
/// * `POST /api/v3/users/ID/report`
/// * `POST /api/v3/forum/ID/report`
/// * `POST /api/v3/forun/post/ID/report`
///
/// See `UsersController.reportHandler(_:data:)`, `ForumController.forumReportHandler(_:data:)`
/// `ForumController.postReportHandler(_:data:)`.
struct ReportData: Content {
    /// An optional message from the submitting user.
    var message: String
}

/// Returned by `Barrel`s as a unit representing a user.
struct SeaMonkey: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
}

/// Used to return a token string for use in HTTP Bearer Authentication.
///
/// Returned by:
/// * `POST /api/v3/auth/login`
/// * `POST /api/v3/auth/recovery`
///
/// See `AuthController.loginHandler(_:)` and `AuthController.recoveryHandler(_:data:)`.
struct TokenStringData: Content {
    /// The token string.
    let token: String
    /// Creates a `TokenStringData` from a `Token`.
    /// - Parameter token: The `Token` associated with the authenticated user.
    init(token: Token) {
        self.token = token.token
    }
}

/// Used to return a `Twarrt`'s data.
///
/// Returned by:
/// * `POST /api/v3/twitarr/create`
/// * `POST /api/v3/twitarr/ID/update`
/// * `POST /api/v3/twitarr/ID/image`
/// * `POST /api/v3/twitarr/ID/image/remove`
/// * `POST /api/v3/twitarr/ID/laugh`
/// * `POST /api/v3/twitarr/ID/like`
/// * `POST /api/v3/twitarr/ID/love`
/// * `POST /api/v3/twitarr/ID/unreact`
/// * `POST /api/v3/twitarr/ID/reply`
/// * `GET /api/v3/twitarr/bookmarks`
/// * `GET /api/v3/twitarr/likes`
/// * `GET /api/v3/twitarr/mentions`
/// * `GET /api/v3/twitarr/`
/// * `GET /api/v3/twitarr/barrel/ID`
/// * `GET /api/v3/twitarr/hashtag/#STRING`
/// * `GET /api/v3/twitarr/search/STRING`
/// * `GET /api/v3/twitarr/user`
/// * `GET /api/v3/twitarr/user/ID`
///
/// See `TwitarrController.twarrtCreateHandler(_:data:)`, `TwitarrController.twarrtUpdateHandler(_:data:)`
/// `TwitarrController. imageHandler(_:data:)`, `TwitarrController.imageRemoveHandler(_:)`
/// `TwitarrController.twarrtLaughHandler(_:)`, `TwitarrController.twarrtLikeHandler(_:)`,
/// `TwitarrController.twarrtLoveHandler(_:)`, `TwitarrController.twarrtUnreactHandler(_:)`,
/// `TwitarrController.replyHandler(_:data:)`, `TwitarrController.bookmarksHandler(_:)`,
/// `TwitarrController.likesHandler(_:)`, `TwitarrController.mentionsHandler(_:)`,
/// `TwitarrController.twarrtsHandler(_:)`, `TwitarrController.twarrtsBarrelHandler(_:)`,
/// `TwitarrController.twarrtsHashtagHandler(_:)`, `TwitarrController.twarrtsSearchHandler(_:)`,
/// `TwitarrController.twarrtsUserHandler(_:)`, `TwitarrController.userHandler(_:)`.
struct TwarrtData: Content {
    /// The ID of the twarrt.
    var twarrtID: Int
    /// The timestamp of the twarrt.
    var createdAt: Date
    /// The ID of the twarrt's author.
    var authorID: UUID
    /// The text of the twarrt.
    var text: String
    /// The filename of the twarrt's optional image.
    var image: String
    /// The ID of the twarrt to which this twarrt is a reply.
    var replyToID: Int?
    /// Whether the current user has bookmarked the twarrt.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the twarrt.
    var userLike: LikeType?
    /// The total number of `LikeType` reactions on the twarrt.
    var likeCount: Int
}

// FIXME: needs bookmark, userLike too?
/// Used to return a `Twarrt`'s data with full user `LikeType` info.
///
/// Returned by: `GET /api/v3/twitarr/ID`
///
/// See `TwitarrController.twarrtHandler(_:)`.
struct TwarrtDetailData: Content {
    /// The ID of the post/twarrt.
    var postID: Int
    /// The timestamp of the post/twarrt.
    var createdAt: Date
    /// The ID of the post/twarrt's author.
    var authorID: UUID
    /// The text of the forum post or twarrt.
    var text: String
    /// The filename of the post/twarrt's optional image.
    var image: String
    /// The ID of the twarrt to which this twarrt is a reply.
    var replyToID: Int?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The seamonkeys with "laugh" reactions on the post/twarrt.
    var laughs: [SeaMonkey]
    /// The seamonkeys with "like" reactions on the post/twarrt.
    var likes: [SeaMonkey]
    /// The seamonkeys with "love" reactions on the post/twarrt.
    var loves: [SeaMonkey]
}

/// Used to return a filename for an uploaded image.
///
/// Returned by: `POST /api/v3/user/image`
///
/// See `UserController.imageHandler(_:data:)`
struct UploadedImageData: Content {
    /// The generated name of the uploaded image.
    var filename: String
}

/// Used to create a new account or sub-account.
///
/// Required by:
/// * `POST /api/v3/user/create`
/// * `POST /api/v3/user/add`
///
/// See `UserController.createHandler(_:data:)`, `UserController.addHandler(_:data:)`.
struct UserCreateData: Content {
    /// The user's username.
    var username: String
    /// The user's password.
    var password: String
}

/// Used to obtain a user's current header information (name and image) for attributed content.
///
/// Returned by:
/// * `GET /api/v3/users/ID/header`
/// * `GET /api/v3/client/user/headers/since/DATE`
///
/// See `UsersController.headerHandler(_:)`, `ClientController.userHeadersHandler(_:)`.
struct UserHeader: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's displayName + username.
    var displayedName: String
    /// The filename of the user's profile image.
    var userImage: String
}

/// Used to obtain user identity and determine whether any cached information may be stale.
///
/// Returned by:
/// * `GET /api/v3/users/ID`
/// * `GET /api/v3/users/find/STRING`
/// * `GET /api/v3/client/user/updates/since/DATE`
///
/// See `UsersController.userHandler(_:)`, `UsersController.findHandler(_:)`,
/// `ClientController.userUpdatesHandler(_:)`.
struct UserInfo: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
    /// Timestamp of last update to the user's profile.
    var updatedAt: Date
}

/// Used to change a user's password.
///
/// Required by: `POST /api/v3/user/password`
///
/// See `UserController.passwordHandler(_:data:)`.
struct UserPasswordData: Content {
    /// The user's desired new password.
    var password: String
}

/// Used to display a user's profile contents for editing.
///
/// Returned by:
/// * `GET /api/v3/user/profile`
/// * `POST /api/v3/user/profile`
///
/// See `UserController.profileHandler(_:)`, `UserController.profileUpdateHandler(_:data:)`.
struct UserProfileData: Content {
    /// The user's username. [not editable here]
    let username: String
    /// A generated displayName + username string. [not editable]
    var displayedName: String
    /// An optional blurb about the user.
    var about: String
    /// An optional name for display alongside the username.
    var displayName: String
    /// An optional email address.
    var email: String
    /// An optional home location (e.g. city).
    var homeLocation: String
    /// An optional greeting/message to visitors of the profile.
    var message: String
    /// An optional preferred form of address.
    var preferredPronoun: String
    /// An optional real name of the user.
    var realName: String
    /// An optional ship cabin number.
    var roomNumber: String
    /// Whether display of the optional fields' data should be limited to logged in users.
    var limitAccess: Bool
}

/// Used to attempt to recover an account in a forgotten-password type scenario.
///
/// Required by: `POST /api/v3/auth/recovery`
///
/// See `AuthController.recoveryHandler(_:data:)`.
struct UserRecoveryData: Content {
    /// The user's username.
    var username: String
    /// The string to use – any one of: password / registration key / recovery key.
    var recoveryKey: String
}

/// Used to broad search for a user based on any of their name fields.
///
/// Returned by:
/// * `GET /api/v3/users/match/allnames/STRING`
/// * `GET /api/v3/client/usersearch`
///
/// See `UsersController.matchAllNamesHandler(_:)`, `ClientController.userSearchHandler(_:)`.
struct UserSearch: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's composed displayName + username + realName.
    var userSearch: String
}

/// Used to change a user's username.
///
/// Required by: `POST /api/v3/user/username`
///
/// See `UserController.usernameHandler(_:data:)`.
struct UserUsernameData: Content {
    /// The user's desired new username.
    var username: String
}

/// Used to verify (register) a created but `.unverified` primary account.
///
/// Required by: `POST /api/v3/user/verify`
///
/// See `UserController.verifyHandler(_:data:)`.
struct UserVerifyData: Content {
    /// The registration code provided to the user.
    var verification: String
}

// MARK: - Validation

extension BarrelCreateData: Validatable, Reflectable {
    /// Validates that `.name` contains a value, and that only one of `.uuidList` or
    /// `.stringList` contains values.
    static func validations() throws -> Validations<BarrelCreateData> {
        var validations = Validations(BarrelCreateData.self)
        try validations.add(\.name, .count(1...))
        validations.add("'uuidList' and 'stringList' cannot both contain values") {
            (data) in
            guard data.uuidList == nil || data.stringList == nil else {
                throw Abort(.badRequest, reason: "'uuidList' and 'stringList' cannot both contain values")
            }
        }
        return validations
    }
}

extension FezContentData: Validatable, Reflectable {
    /// Validates that `.title`, `.info`, `.location` have values of at least 2
    /// characters, that `.startTime` and `.endTime` have date values.
    static func validations() throws -> Validations<FezContentData> {
        var validations = Validations(FezContentData.self)
        try validations.add(\.title, .count(2...))
        try validations.add(\.info, .count(2...))
        try validations.add(\.location, .count(2...))
        validations.add(".startTime and .endTime must contain dates or nothing") {
            (data) in
            guard (Double(data.startTime) != nil) || data.startTime.isEmpty else {
                throw Abort(.badRequest, reason: "'startTime' must be either a numeric date or empty")
            }
            guard (Double(data.endTime) != nil) || data.endTime.isEmpty else {
                throw Abort(.badRequest, reason: "'endTime' must be either a numeric date or empty")
            }
        }
        return validations
    }
}

extension ForumCreateData: Validatable, Reflectable {
    /// Validates that `.title` and initial post `.text`  both contain values.
    static func validations() throws -> Validations<ForumCreateData> {
        var validations = Validations(ForumCreateData.self)
        try validations.add(\.title, .count(1...))
        try validations.add(\.text, .count(1...))
        return validations
    }
}

extension PostContentData: Validatable, Reflectable {
    /// Validates that `.text` contains a value.
    static func validations() throws -> Validations<PostContentData> {
        var validations = Validations(PostContentData.self)
        try validations.add(\.text, .count(1...))
        return validations
    }
}

extension PostCreateData: Validatable, Reflectable {
    /// Validates that `.text` contains a value.
    static func validations() throws -> Validations<PostCreateData> {
        var validations = Validations(PostCreateData.self)
        try validations.add(\.text, .count(1...))
        return validations
    }
}

extension UserCreateData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more characters beginning with an alphanumeric,
    /// and `.password` is least 6 characters in length.
    static func validations() throws -> Validations<UserCreateData> {
        var validations = Validations(UserCreateData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics + .usernameSeparators))
        validations.add("username must start with an alphanumeric") {
            (data) in
            guard let first = data.username.unicodeScalars.first,
                !CharacterSet.usernameSeparators.contains(first) else {
                    throw Abort(.badRequest, reason: "username must start with an alphanumeric")
            }
        }
        try validations.add(\.password, .count(6...))
        return validations
    }
}

extension UserPasswordData: Validatable, Reflectable {
    /// Validates that the new password is at least 6 characters in length.
    static func validations() throws -> Validations<UserPasswordData> {
        var validations = Validations(UserPasswordData.self)
        try validations.add(\.password, .count(6...))
        return validations
    }
}

extension UserRecoveryData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more alphanumeric characters,
    /// and `.recoveryCode` is at least 6 character in length (minimum for
    /// both registration codes and passwords).
    static func validations() throws -> Validations<UserRecoveryData> {
        var validations = Validations(UserRecoveryData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        try validations.add(\.recoveryKey, .count(6...))
        return validations
    }
}

extension UserUsernameData: Validatable, Reflectable {
    /// Validates that the new username is 1 or more characters and begins with an
    /// alphanumeric.
    static func validations() throws -> Validations<UserUsernameData> {
        var validations = Validations(UserUsernameData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics + .usernameSeparators))
        validations.add("username must start with an alphanumeric") {
            (data) in
            guard let first = data.username.unicodeScalars.first,
                !CharacterSet.usernameSeparators.contains(first) else {
                    throw Abort(.badRequest, reason: "username must start with an alphanumeric")
            }
        }
        return validations
    }
}

extension UserVerifyData: Validatable, Reflectable {
    /// Validates that a `.verification` registration code is either 6 or 7 alphanumeric
    /// characters in length (allows for inclusion or exclusion of the space).
    static func validations() throws -> Validations<UserVerifyData> {
        var validations = Validations(UserVerifyData.self)
        try validations.add(\.verification, .count(6...7) && .characterSet(.alphanumerics + .whitespaces))
        return validations
    }
}
