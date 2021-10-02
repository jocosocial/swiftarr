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

/// An announcement to display to all users. 
/// 
/// - Note: Admins can modify Announcements, but should only do so to correct typos or change the displayUntil time. Therefore if a user has seen an announcement,
/// they need not be notified again if the announcement is edited. Any material change to the content of an announcement should be done via a **new** announcement, 
/// so that user notifications work correctly.
///
/// Returned by:
/// * `GET /api/v3/notification/announcements`
/// * `GET /api/v3/notification/announcement/ID` for admins/THO only.
struct AnnouncementData: Content {
	/// Only THO and admins need to send Announcement IDs back to the API (to modify or delete announcements, for example), but caching clients can still use the ID
	/// to correlate announcements returned by the API with cached ones.
	var id: Int
	/// The author of the announcement.
	var author: UserHeader
	/// The contents of the announcement.
	var text: String
	/// When the announcement was last modified.
	var updatedAt: Date
	/// Announcements are considered 'active' until this time. After this time, `GET /api/v3/notification/announcements` will no longer return the announcement,
	/// and caching clients should stop showing it to users.
	var displayUntil: Date
	/// TRUE if the announcement has been deleted. Only THO/admins can fetch deleted announcements; will always be FALSE for other users.
	var isDeleted: Bool
}

extension AnnouncementData {
	init(from: Announcement, authorHeader: UserHeader) throws {
		id = try from.requireID()
		author = authorHeader
		text = from.text
		updatedAt = from.updatedAt ?? Date()
		displayUntil = from.displayUntil
		isDeleted = false
		if let deleteTime = from.deletedAt, deleteTime < Date() {
			isDeleted = true
		}
	}
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

extension BarrelCreateData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(name.count > 0, forKey: .name, or: "Barrel name cannot be empty.")
    	tester.validate(name.count <= 100, forKey: .name, or: "Barrel name length is limited to 100 characters.")
    	if uuidList != nil && stringList != nil {
    		tester.addValidationError(forKey: nil, errorString: "'uuidList' and 'stringList' cannot both contain values")
		}
	}
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

extension BarrelData {
	init(barrel: Barrel, users: [User]? = nil) throws {
		barrelID = try barrel.requireID()
		name = barrel.name
		seamonkeys = try users?.map { try SeaMonkey(user: $0) } ?? []
		stringList = barrel.userInfo["userWords"]
	}
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
    var blockedUsers: [UserHeader]
}

/// Used to return the ID and title of a `Category`. 
///
/// Returned by:
/// * `GET /api/v3/forum/categories`
/// * `GET /api/v3/forum/catgories/ID`
///
/// See `ForumController.categoriesHandler(_:)`
struct CategoryData: Content {
    /// The ID of the category.
    var categoryID: UUID
    /// The title of the category.
    var title: String
    /// If TRUE, the user cannot create/modify threads in this forum. Should be sorted to top of category list.
    var isRestricted: Bool
    /// The number of threads in this category
    var numThreads: Int32
    ///The threads in the category. Only populated for /categories/ID.
    var forumThreads: [ForumListData]?
}

extension CategoryData {
	init(_ cat: Category, restricted: Bool, forumThreads: [ForumListData]? = nil) throws {
		categoryID = try cat.requireID()
		title = cat.title
		isRestricted = restricted
		numThreads = cat.forumCount
		self.forumThreads = forumThreads
	}
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

/// Used to return the day's theme.
///
/// Returned by: `GET /api/v3/notifications/dailythemes`
///
struct DailyThemeData: Content {
    /// The theme's ID Probably only useful for admins in order to edit or delete themes.
    var themeID: UUID
	/// A short string describing the day's theme. e.g. "Cosplay Day", or "Pajamas Day", or "Science Day".
	var title: String
	/// A longer string describing the theme, possibly with a call to action for users to participate.
	var info: String
	/// An image that relates to the theme.
	var image: String?
	/// Day of cruise, counted from `Settings.shared.cruiseStartDate`. 0 is embarkation day. Values could be negative (e.g. Day -1 is "Anticipation Day")
	var cruiseDay: Int32				
}

extension DailyThemeData {
	init(_ theme: DailyTheme) throws {
		self.themeID = try theme.requireID()
        self.title = theme.title
        self.info = theme.info
        self.image = theme.image
        self.cruiseDay = theme.cruiseDay
	}
}

/// A feature that has been turned off by the server. If the `appName` is `all`, the indicated `featureName` is disabled at the API level for 
/// this feature and all relevant endpoints will return errors. For any other value of appName, the API still works, but the indicated client apps should
/// not allow the feature to be accessed. The goal is to be able to disable code that is impacting server stability or performance without shutting down
/// the server entirely or disallowing specific clients entirely. 
///
/// Used in `UserNotificationData`.
struct DisabledFeature: Content {
	/// AppName and featureName act as a grid, allowing a specific feature to be disabled only in a specific app. If the appName is `all`, the server
	/// code for the feature may be causing the issue, requiring the feature be disabled for all clients.
	var appName: SwiftarrClientApp
	/// The feature to disable. Features roughly match API controller groups. 
	var featureName: SwiftarrFeature
}

/// Used to obtain an event's details.
///
/// Returned by:
/// * `GET /api/v3/events`
/// * `GET /api/v3/events/favorites`
///
/// See `EventController.eventsHandler(_:)`, `EventController.favoritesHandler(_:)`.
struct EventData: Content {
    /// The event's ID. This is the Swiftarr database record for this event.
    var eventID: UUID
    /// The event's UID. This is the VCALENDAR/ICS File/sched.com identifier for this event--what calendar software uses to correllate whether 2 events are the same event.
    var uid: String
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

extension EventData {
	init(_ event: Event, isFavorite: Bool = false) throws {
		eventID = try event.requireID()
		uid = event.uid
		title = event.title
		description = event.info
		startTime = event.startTime
		endTime = event.endTime
		location = event.location
		eventType = event.eventType.label
		forum = event.$forum.id
		self.isFavorite = isFavorite
	}
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
    var fezType: FezType
    /// The title for the FriendlyFez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time for the fez.
    var startTime: Date?
    /// The ending time for the fez.
    var endTime: Date?
    /// The location for the fez.
    var location: String?
    /// The minimum number of seamonkeys needed for the fez.
    var minCapacity: Int
    /// The maximum number of seamonkeys for the fez.
    var maxCapacity: Int
    /// Users to add to the fez upon creation. The creator is always added as the first user.
    var initialUsers: [UUID]
}

extension FezContentData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	if fezType != .closed {
			tester.validate(title.count >= 2, forKey: .title, or: "title field has a 2 character minimum")
			tester.validate(title.count <= 100, forKey: .title, or: "title field has a 100 character limit")
			tester.validate(info.count >= 2, forKey: .info, or: "info field has a 2 character minimum")
			tester.validate(info.count <= 2048, forKey: .info, or: "info field length of \(info.count) is over the 2048 character limit")
			if let loc = location {
				tester.validate(loc.count >= 3, forKey: .location, or: "location field has a 3 character minimum") 
			}
		}
    	
    	// TODO: validations for startTime and endTime  	
	}
}

/// Used to return a `FriendlyFez`'s data.
///
/// Returned by these methods, with `members` set to nil.
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
/// Returned by these  methods, with `members` populated.
/// * `GET /api/v3/fez/ID`
/// * `POST /api/v3/fez/ID/post`
/// * `POST /api/v3/fex/ID/post/ID/delete`

/// See `FezController.createHandler(_:data:)`, `FezController.joinHandler(_:)`,
/// `FezController.unjoinHandler(_:)`, `FezController.joinedHandler(_:)`
/// `FezController.openhandler(_:)`, `FezController.ownerHandler(_:)`,
/// `FezController.userAddHandler(_:)`, `FezController.userRemoveHandler(_:)`,
/// `FezController.cancelHandler(_:)`.
struct FezData: Content, ResponseEncodable {
    /// The ID of the fez.
    var fezID: UUID
    /// The fez's owner.
    var owner: UserHeader
    /// The `FezType` .label of the fez.
    var fezType: FezType
    /// The title of the fez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time of the fez.
    var startTime: Date?
    /// The ending time of the fez.
    var endTime: Date?
    /// The location for the fez.
    var location: String?
    /// How many users are currently members of the fez. Can be larger than maxParticipants; which indicates a waitlist.
	var participantCount: Int
    /// The min number of people for the activity. Set by the host. Fezzes may?? auto-cancel if the minimum participant count isn't met when the fez is scheduled to start.
	var minParticipants: Int
    /// The max number of people for the activity. Set by the host.
	var maxParticipants: Int
	/// The most recent of: Creation time for the fez, time of the last post (may not exactly match post time), user add/remove, or update to fezzes' fields. 
	var lastModificationTime: Date
    
    /// FezData.MembersOnlyData returns data only available to participants in a Fez. 
    struct MembersOnlyData: Content, ResponseEncodable {
		/// The users participating in the fez.
		var participants: [UserHeader]
		/// The users on a waiting list for the fez.
		var waitingList: [UserHeader]
		/// How many posts the user can see in the fez. The count is returned even for calls that don't return the actual posts, but is not returned for 
		/// fezzes where the user is not a member. PostCount does not include posts from blocked/muted users.
		var postCount: Int
		/// How many posts the user has read. If postCount > readCount, there's posts to be read. UI can also use readCount to set the initial view 
		/// to the first unread message.ReadCount does not include posts from blocked/muted users.
		var readCount: Int
		/// The FezPosts in the fez discussion. Methods that return arrays of Fezzes, or that add or remove users, do not populate this field (it will be nil).
		var posts: [FezPostData]?
	}
	
	/// Will be nil if user is not a member of the fez (in the participant or waiting lists).
	var members: MembersOnlyData?
}

extension FezData {
	init(fez: FriendlyFez, owner: UserHeader) throws {
		self.fezID = try fez.requireID()
		self.owner = owner
		self.fezType = fez.fezType
		self.title = fez.moderationStatus.showsContent() ? fez.title : "Fez Title is under moderator review"
		self.info = fez.moderationStatus.showsContent() ? fez.info : "Fez Information field is under moderator review"
		self.startTime = fez.startTime
		self.endTime = fez.endTime
		self.location = fez.moderationStatus.showsContent() ? fez.location : "Fez Location field is under moderator review"
		self.lastModificationTime = fez.updatedAt ?? Date()
		self.participantCount = fez.participantArray.count
		self.minParticipants = fez.minCapacity
		self.maxParticipants = fez.maxCapacity
		self.members = nil
	}
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
    /// The time the post was submitted.
    var timestamp: Date
    /// The image content of the fez post.
    var image: String?
}

extension FezPostData {    
    init(post: FezPost) throws {
    	self.postID = try post.requireID()
    	self.authorID = post.$author.id
    	self.text = post.text
    	self.timestamp = post.createdAt ?? post.updatedAt ?? Date()
    	self.image = post.image
    }
}

/// Used to create a new `Forum`.
///
/// Required by: `POST /api/v3/forum/categories/ID/create`
///
/// See `ForumController.forumCreateHandler(_:data:)`.
struct ForumCreateData: Content {
    /// The forum's title.
    var title: String
    /// The first post in the forum. 
	var firstPost: PostContentData
}

extension ForumCreateData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(title.count >= 2, forKey: .title, or: "forum title has a 2 character minimum")
    	tester.validate(title.count <= 100, forKey: .title, or: "forum title has a 100 character limit")
	}
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
    /// The ID of the forum's containing Category..
    var categoryID: UUID
    /// The forum's title
    var title: String
    /// The forum's creator.
	var creator: UserHeader
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether the user has favorited forum.
    var isFavorite: Bool
    /// The total number of posts in the thread. Could be > posts.count even if all the viewable posts are being returned. If start + limit >= totalPosts this response has the last post in the thread.
	var totalPosts: Int
	/// The index number of the first post in the `posts` array. 0 is the index of the first post in the forum. This number is usually  a multiple of `limit` and indicates the page of results.
	var start: Int
	/// The number of posts the server attempted to gather. posts.count may be less than this number if posts were filtered out by blocks/mutes, or if start + limit > totalPosts.
	var limit: Int
    /// The posts in the forum.
    var posts: [PostData]
}

extension ForumData {
    init(forum: Forum, creator: UserHeader, isFavorite: Bool, posts: [PostData]) throws {
    	guard creator.userID == forum.$creator.id else {
    		throw Abort(.internalServerError, reason: "Internal server error--Forum's creator does not match.")
    	}
    
		forumID = try forum.requireID()
		categoryID = forum.$category.id
		title = forum.moderationStatus.showsContent() ? forum.title : "Forum Title is under moderator review"
		self.creator = creator
		isLocked = forum.moderationStatus == .locked
		self.isFavorite = isFavorite
		self.posts = posts
		self.totalPosts = 1
		self.start = 0
		self.limit = 50
    }
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
    /// The forum's creator.
	var creator: UserHeader
    /// The forum's title.
    var title: String
    /// The number of posts in the forum. 
    var postCount: Int
    /// The number of posts the user has read.  Specifically, this will be the number of posts the forum contained the last time the user called a fn that returned a `ForumData`.
    /// Blocked and muted posts are included in this number, but not returned in the array of posts.
    var readCount: Int
    /// Time forum was created.
    var createdAt: Date
    /// The last user to post to the forum. Nil if there are no posts in the forum.
	var lastPoster: UserHeader?
    /// Timestamp of most recent post. Needs to be optional because admin forums may be empty.
    var lastPostAt: Date?
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether user has favorited forum.
    var isFavorite: Bool
}

extension ForumListData {
	init(forum: Forum, creator: UserHeader, postCount: Int, readCount: Int, lastPostAt: Date?, lastPoster: UserHeader?, isFavorite: Bool) throws {
    	guard creator.userID == forum.$creator.id else {
    		throw Abort(.internalServerError, reason: "Internal server error--Forum's creator does not match.")
    	}
		self.forumID = try forum.requireID()
		self.creator = creator
		self.title = forum.moderationStatus.showsContent() ? forum.title : "Forum Title is under moderator review"
		self.postCount = postCount
		self.readCount = readCount
		self.createdAt = forum.createdAt ?? Date()
		self.lastPostAt = lastPostAt
		self.lastPoster = lastPoster
		self.isLocked = forum.moderationStatus == .locked
		self.isFavorite = isFavorite
    }
}

/// Used to return a (partial) list of forums along with the number of forums in the found set. Similar to CategoryData, but the 
/// forums need not be from the same category. Instead, this returns forums that match a common attribute acoss all categores.
///
/// Returned by:
/// * `GET /api/v3/forum/match/STRING`
/// * `GET /api/v3/forum/favorites`
/// * `GET /api/v3/forum/owner`
///
/// See `ForumController.categoriesHandler(_:)`
struct ForumSearchData: Content {
	/// The index number of the first post in the `posts` array. 0 is the index of the first post in the forum. This number is usually  a multiple of `limit` and indicates the page of results.
	var start: Int
	/// The number of posts the server attempted to gather. posts.count may be less than this number if posts were filtered out by blocks/mutes, or if start + limit > totalPosts.
	var limit: Int
    /// The number of threads in this category
    var numThreads: Int
    ///The threads in the category. Only populated for /categories/ID.
    var forumThreads: [ForumListData]
}


/// Used to upload an image file or refer to an already-uploaded image. Either `filename` or `image` should always be set. 
/// If both are set, `filename` is ignored and `image` is processed and saved with a new name. A more Swift-y way to do this
/// would be an Enum with associated values, except Codable support becomes a pain and makes it difficult to understand 
/// what the equivalent JSON struct will look like.
///
/// Required by: `POST /api/v3/user/image`
/// Incorporated into `PostContentData`, which is in turn required by several routes.
///
/// See `UserController.imageHandler(_:data)`.
struct ImageUploadData: Content {
    /// The filename of an existing image previously uploaded to the server. Ignored if image is set.
    var filename: String?
    /// The image in `Data` format. 
    var image: Data?
}

extension ImageUploadData {
	/// Failable initializer; either filename or image must be non-nil and non-empty.
	init?(_ filename: String?, _ image: Data?) {
		if let fn = filename, !fn.isEmpty {
			self.filename = fn
		}
		if let img = image, !img.isEmpty {
			self.image = img
		}
		if self.filename == nil && self.image == nil {
			return nil
		}
	}
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
    var mutedUsers: [UserHeader]
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
/// * `GET /api/v3/users/ID/note`
/// * `POST /api/v3/user/note`
///
/// See `UserController.notesHandler(_:)`, `UserController.noteHandler(_:data:)`.
struct NoteData: Content {
    /// Timestamp of the note's creation.
    let createdAt: Date
    /// Timestamp of the note's last update.
    let updatedAt: Date
    /// The user the note is written about. The target user does not get to see notes written about them.
    let targetUser: UserHeader
    /// The text of the note.
    var note: String
}

extension NoteData {
	init(note: UserNote, targetUser: User) throws {
		self.createdAt = note.createdAt ?? Date()
		self.updatedAt = note.updatedAt ?? Date()
		self.targetUser = try UserHeader(user: targetUser)
		self.note = note.note
	}
}

/// Used to create or update a `ForumPost` or `Twarrt`. 
///
/// Required by:
/// * `POST /api/v3/forum/ID/create`
/// * `POST /api/v3/forum/post/ID`
/// * `POST /api/v3/forum/post/ID/update`
/// * `POST /api/v3/twitarr/create`
/// * `POST /api/v3/twitarr/ID/reply`
/// * `POST /api/v3/twitarr/ID/update`
/// * `POST /api/v3/fez/ID/post`
///
/// See `ForumController.postUpdateHandler(_:data:)`.
struct PostContentData: Content {
    /// The new text of the forum post.
    var text: String
    /// An array of up to 4 images (1 when used in a Fez post). Each image can specify either new image data or an existing image filename. 
	/// For new posts, images will generally contain all new image data. When editing existing posts, images may contain a mix of new and existing images. 
	/// Reorder ImageUploadDatas to change presentation order. Set images to [] to remove images attached to post when editing.
    var images: [ImageUploadData]
}

extension PostContentData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(text.count > 0, forKey: .text, or: "post text cannot be empty.")
    	tester.validate(text.count < 2048, forKey: .text, or: "post length of \(text.count) is over the 2048 character limit")
    	tester.validate(images.count < 5, forKey: .images, or: "posts are limited to 4 image attachments")
    	let lines = text.replacingOccurrences(of: "\r\n", with: "\r").components(separatedBy: .newlines).count
    	tester.validate(lines <= 25, forKey: .images, or: "posts are limited to 25 lines of text")
	}
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
    /// The post's author.
    var author: UserHeader
    /// The text of the post.
    var text: String
    /// The filenames of the post's optional images.
    var images: [String]?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the post.
    var userLike: LikeType?
    /// The total number of `LikeType` reactions on the post.
    var likeCount: Int
}

extension PostData {    
    init(post: ForumPost, author: UserHeader, bookmarked: Bool, userLike: LikeType?, likeCount: Int, overrideQuarantine: Bool = false) throws {
		postID = try post.requireID()
		createdAt = post.createdAt ?? Date()
		self.author = author
		text = post.isQuarantined && !overrideQuarantine ? "This post is under moderator review." : post.text
		images = post.isQuarantined && !overrideQuarantine ? nil : post.images
		isBookmarked = bookmarked
		self.userLike = userLike
		self.likeCount = likeCount
    }
    
    // For newly created posts
    init(post: ForumPost, author: UserHeader) throws {
		postID = try post.requireID()
		createdAt = post.createdAt ?? Date()
		self.author = author
		text = post.isQuarantined ? "This post is under moderator review." : post.text
		images = post.isQuarantined ? nil : post.images
		isBookmarked = false
		self.userLike = nil
		self.likeCount = 0
    }
}

/// Used to return info about a search for `ForumPost`s. Like forums, this returns an array of `PostData.`
/// However, this gives the results of a search for posts across all the forums.
///
/// Returned by: `GET /api/v3/forum/post/search`
/// 
struct PostSearchData: Content {
	/// The search query used to create these results. 
	var queryString: String
    /// The total number of posts in the result set.
	var totalPosts: Int
	/// The index number of the first post in the `posts` array. 0 is the index of the first post in the forum. This number is usually  a multiple of `limit` and indicates the page of results.
	var start: Int
	/// The number of posts the server attempted to gather. posts.count may be less than this number if posts were filtered out by blocks/mutes, or if start + limit > totalPosts.
	var limit: Int
    /// The posts in the forum.
    var posts: [PostData]
}

/// Used to return a `ForumPost`'s data with full user `LikeType` info.
///
/// Returned by: `GET /api/v3/forum/post/ID`
///
/// See `ForumController.postHandler(_:)`.
struct PostDetailData: Content {
    /// The ID of the post.
    var postID: Int
    /// The ID of the Forum containing the post.
    var forumID: UUID
    /// The timestamp of the post.
    var createdAt: Date
    /// The post's author.
    var author: UserHeader
    /// The text of the forum post.
    var text: String
    /// The filenames of the post's optional images.
    var images: [String]?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the post.
    var userLike: LikeType?
    /// The seamonkeys with "laugh" reactions on the post.
    var laughs: [SeaMonkey]
    /// The seamonkeys with "like" reactions on the post.
    var likes: [SeaMonkey]
    /// The seamonkeys with "love" reactions on the post.
    var loves: [SeaMonkey]
}

extension PostDetailData {
	// Does not fill in isBookmarked, userLike, and reaction arrays.
    init(post: ForumPost, author: UserHeader, overrideQuarantine: Bool = false) throws {
		postID = try post.requireID()
		forumID = post.$forum.id
		createdAt = post.createdAt ?? Date()
		self.author = author
		text = post.isQuarantined && !overrideQuarantine ? "This post is under moderator review." : post.text
		images = post.isQuarantined && !overrideQuarantine ? nil : post.images
		isBookmarked = false
		self.userLike = nil
		laughs = []
		likes = []
		loves = []
    }

}

/// Used to return a user's public profile contents. For viewing/editing a user's own profile, see `UserProfileData`.
///
/// Returned by: `GET /api/v3/users/ID/profile`
///
/// See `UsersController.profileHandler(_:)`.
struct ProfilePublicData: Content {
    /// Basic info abou thte user--their ID, username, displayname, and avatar image.
    var header: UserHeader
    /// An optional real world name of the user.
    var realName: String
    /// An optional preferred pronoun or form of address.
    var preferredPronoun: String
    /// An optional home location for the user.
    var homeLocation: String
    /// An optional cabin number for the user.
    var roomNumber: String
    /// An optional email address for the user.
    var email: String
    /// An optional blurb about the user.
    var about: String
    /// An optional greeting/message to visitors of the profile.
    var message: String
    /// A UserNote owned by the visiting user, about the profile's user (see `UserNote`).
    var note: String?
}

extension ProfilePublicData {
	init(user: User, note: String?, requester: User) throws {
		self.header = try UserHeader(user: user)
		if !user.moderationStatus.showsContent() && !requester.accessLevel.hasAccess(.moderator) { 
			self.header.displayName = nil
			self.header.userImage = nil 
			self.about = ""
			self.email = ""
			self.homeLocation = ""
			self.message = "This profile is under moderator review"
			self.preferredPronoun = ""
			self.realName = ""
			self.roomNumber = ""
			self.note = note
		}
		else if requester.accessLevel == .banned {
			self.about = ""
			self.email = ""
			self.homeLocation = ""
			self.message = "You must be logged in to view this user's Profile details."
			self.preferredPronoun = ""
			self.realName = ""
			self.roomNumber = ""
		}
		else {
			self.about = user.about ?? ""
			self.email = user.email ?? ""
			self.homeLocation = user.homeLocation ?? ""
			self.message = user.message ?? ""
			self.preferredPronoun = user.preferredPronoun ?? ""
			self.realName = user.realName ?? ""
			self.roomNumber = user.roomNumber ?? ""
			self.note = note
		}
	}
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

extension SeaMonkey {
	init(user: User) throws {
		userID = try user.requireID()
		username = user.username
	}
	
	init(header: UserHeader) {
		userID = header.userID
		username = header.username
	}
	
	static var Blocked: SeaMonkey { .init(userID: Settings.shared.blockedUserID, username: "BlockedUser") }
	static var Available: SeaMonkey { .init(userID: Settings.shared.friendlyFezID, username: "AvailableSlot") }
}

/// Used to return a token string for use in HTTP Bearer Authentication.
/// 
/// Clients can use the `userID` field  to validate the user that logged in matches the user they *thiought* was logging in.
/// This guards against a situation where one user changes their username to the previous username value
/// of another user. A client using `/client/user/updates/since` could end up associating a login with the wrong
/// `User` because they were matching on `username` instead of `userID`.  That is, a user picks a username and logs in
/// with their own password. Their client has a (out of date) stored User record, for a different user, that had the same username.
///
/// Returned by:
/// * `POST /api/v3/auth/login`
/// * `POST /api/v3/auth/recovery`
///
/// See `AuthController.loginHandler(_:)` and `AuthController.recoveryHandler(_:data:)`.
struct TokenStringData: Content {
    /// The user ID of the newly logged in user. 
    var userID: UUID
    /// The user's access level.
	var accessLevel: UserAccessLevel
    /// The token string.
    let token: String

    /// Creates a `TokenStringData` from a `UserAccessLevel` and a `Token`. The Token must be associated with a `User`, 
    /// but the User object does not need to be attached.
    init(accessLevel: UserAccessLevel, token: Token) {
    	self.userID = token.$user.id
    	self.accessLevel = accessLevel
        self.token = token.token
    }
    
    /// Creates a `TokenStringData` from a `User` and a `Token`. The Token must be associated with  the user, 
    /// but the User object does not need to be attached.
    init(user: User, token: Token) throws {
    	guard try token.$user.id == user.requireID() else {
    		throw Abort(.internalServerError, reason: "Attempt to create TokenStringData for token not assigned to User")
    	}
    	self.userID = token.$user.id
    	self.accessLevel = user.accessLevel
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
    /// The twarrt's author.
    var author: UserHeader
    /// The text of the twarrt.
    var text: String
    /// The filenames of the twarrt's optional images.
    var images: [String]?
    /// If this twarrt is part of a Reply Group, the ID of the group. If replyGroupID == twarrtID, this twarrt is the start of a Reply Group.
    var replyGroupID: Int?
    /// Whether the current user has bookmarked the twarrt.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the twarrt.
    var userLike: LikeType?
    /// The total number of `LikeType` reactions on the twarrt.
    var likeCount: Int
}

extension TwarrtData {
    init(twarrt: Twarrt, creator: UserHeader, isBookmarked: Bool, userLike: LikeType?, likeCount: Int, overrideQuarantine: Bool = false) throws {
    	guard creator.userID == twarrt.$author.id else {
    		throw Abort(.internalServerError, reason: "Internal server error--Twarrt's creator does not match.")
    	}
		twarrtID = try twarrt.requireID()
		createdAt = twarrt.createdAt ?? Date()
		self.author = creator
		text = twarrt.isQuarantined && !overrideQuarantine ? "This post is under moderator review." : twarrt.text
		images = twarrt.isQuarantined && !overrideQuarantine ? nil : twarrt.images
		replyGroupID = twarrt.$replyGroup.id
		self.isBookmarked = isBookmarked
		self.userLike = userLike
		self.likeCount = likeCount
    }
}

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
    /// The twarrt's author.
    var author: UserHeader
    /// The text of the forum post or twarrt.
    var text: String
    /// The filenames of the post/twarrt's optional images.
    var images: [String]?
    /// The ID of the twarrt to which this twarrt is a reply.
    var replyGroupID: Int?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the twarrt.
    var userLike: LikeType?
    /// The seamonkeys with "laugh" reactions on the post/twarrt.
    var laughs: [SeaMonkey]
    /// The seamonkeys with "like" reactions on the post/twarrt.
    var likes: [SeaMonkey]
    /// The seamonkeys with "love" reactions on the post/twarrt.
    var loves: [SeaMonkey]
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
    /// Optional verification code. If set, must be a valid code. On success, user will be created with .verified access level, consuming this code.
    /// See `/api/v3/user/verify`
    var verification: String?
}

extension UserCreateData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(password.count >= 6, forKey: .password, or: "password has a 6 character minimum")
    	tester.validate(password.count <= 50, forKey: .password, or: "password has a 50 character limit")
    	usernameValidations(username: username).forEach {
    		tester.addValidationError(forKey: .username, errorString: $0)
    	}
		// Registration code can be nil, but if it isn't, it must be a properly formed code.
		if let normalizedCode = verification?.lowercased().replacingOccurrences(of: " ", with: ""), normalizedCode.count > 0 {
			if normalizedCode.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil || normalizedCode.count != 6  {
    			tester.addValidationError(forKey: .verification, errorString: "Malformed registration code. Registration code " +
						"must be 6 alphanumeric letters; spaces optional")
			}
		}
	}
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
    /// The user's username.
    var username: String
    /// The user's displayName.
    var displayName: String?
    /// The user's avatar image.
    var userImage: String?
}

extension UserHeader {
	init(user: User) throws {
		self.userID = try user.requireID()
		self.username = user.username
		self.displayName = user.displayName
		self.userImage = user.userImage
	}
	
	static var Blocked: UserHeader { .init(userID: Settings.shared.blockedUserID, username: "BlockedUser", 
			displayName: "BlockedUser", userImage: "") }
}

/// Provides updates about server global state and the logged in user's notifications. 
/// `userNotificationHandler()` is intended to be called frequently by clients (I mean, don't call it once a second).
/// 
/// Returned by AlertController.userNotificationHandler()
struct UserNotificationData: Content {
	/// Always an ISO 8601 date in UTC, like "2020-03-07T12:00:00Z"
	var serverTime: String
	/// Server Time Zone offset, in seconds from UTC. One hour before UTC is -3600. EST  timezone is -18000.
	var serverTimeOffset: Int
	/// Human-readable time zone name, like "EDT"
	var serverTimeZone: String
	/// Features that are turned off by the server. If the `appName` for a feature is `all`, the feature is disabled at the API layer.
	/// For all other appName values, the disable is just a notification that the client should not show the feature to users.
	/// If the list is empty, no features have been deisabled. 
	var disabledFeatures: [DisabledFeature]

	/// Count of all active announcements 
	var activeAnnouncementCount: Int
	
/// All fields below this line will be 0 or null if called when not logged in.
	
	/// Count of announcements the user has not yet seen. 0 if not logged in.
	var newAnnouncementCount: Int
	
	/// Number of twarrts that @mention the user. 0 if not logged in.
	var twarrtMentionCount: Int
	/// Number of twarrt @mentions that the user has not read (by visiting the twarrt mentions endpoint; reading twarrts in the regular feed doesn't count). 0 if not logged in.
	var newTwarrtMentionCount: Int
	
	/// Number of forum posts that @mention the user. 0 if not logged in.
	var forumMentionCount: Int
	/// Number of forum post @mentions the user has not read. 0 if not logged in.
	var newForumMentionCount: Int
	
	/// Count of # of Seamail threads with new messages. NOT total # of new messages-a single seamail thread with 10 new messages counts as 1. 0 if not logged in.
	var newSeamailMessageCount: Int
	/// Count of # of Fezzes with new messages. 0 if not logged in.
	var newFezMessageCount: Int
	
	/// The start time of the earliest event that the user has followed with a start time > now. nil if not logged in.
	var nextFollowedEventTime: Date?
	
	// I see where alert words can be set, but nowhere do I see alert words implemented to actually alert a user.
//	let alertWordNotificationCount: Int
}

extension UserNotificationData	{
	init(user: User, newFezCount: Int, newSeamailCount: Int, newAnnouncementCount: Int, activeAnnouncementCount: Int, 
			nextEvent: Date?, disabledFeatures: [DisabledFeature]) {
		serverTime = ISO8601DateFormatter().string(from: Date())
		serverTimeOffset = TimeZone.autoupdatingCurrent.secondsFromGMT()
		serverTimeZone = TimeZone.autoupdatingCurrent.abbreviation() ?? ""
		self.disabledFeatures = disabledFeatures
		self.activeAnnouncementCount = activeAnnouncementCount
		self.newAnnouncementCount = newAnnouncementCount
		self.twarrtMentionCount = user.twarrtMentions
		self.newTwarrtMentionCount = max(user.twarrtMentions - user.twarrtMentionsViewed, 0)
		self.forumMentionCount = user.forumMentions
		self.newForumMentionCount = max(user.forumMentions - user.forumMentionsViewed, 0)
		self.newSeamailMessageCount = newSeamailCount
		self.newFezMessageCount = newFezCount
		self.nextFollowedEventTime = nextEvent
	}
	
	// Initializes an dummy struct, for when there's no user logged in.
	init() {
		serverTime = ISO8601DateFormatter().string(from: Date())
		serverTimeOffset = TimeZone.autoupdatingCurrent.secondsFromGMT()
		serverTimeZone = TimeZone.autoupdatingCurrent.abbreviation() ?? ""
		self.disabledFeatures = []
		self.activeAnnouncementCount = 0
		self.newAnnouncementCount = 0
		self.twarrtMentionCount = 0
		self.newTwarrtMentionCount = 0
		self.forumMentionCount = 0
		self.newForumMentionCount = 0
		self.newSeamailMessageCount = 0
		self.newFezMessageCount = 0
		self.nextFollowedEventTime = nil
	}
}

/// Used to change a user's password. Even when already logged in, users need to provide their current password to set a new password.
///
/// Required by: `POST /api/v3/user/password`
///
/// See `UserController.passwordHandler(_:data:)`.
struct UserPasswordData: Content {
    /// The user's current password.
    var currentPassword: String
    /// The user's desired new password.
    var newPassword: String
}

extension UserPasswordData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(newPassword.count >= 6, forKey: .newPassword, or: "password has a 6 character minimum")
    	tester.validate(newPassword.count <= 50, forKey: .newPassword, or: "password has a 50 character limit")
	}
}

/// Used to edit the current user's profile contents. For profile data on users, see `ProfilePublicData`.
///
/// Required by: 
/// * `POST /api/v3/user/profile`
///
/// Returned by:
/// * `GET /api/v3/user/profile`
/// * `POST /api/v3/user/profile`
///
/// See `UserController.profileHandler(_:)`, `UserController.profileUpdateHandler(_:data:)`.
struct UserProfileUploadData: Content {
    /// Basic info about the user--their ID, username, displayname, and avatar image. May be nil on POST.
    var header: UserHeader?
    /// The displayName, again. Will be equal to header.displayName in results. When POSTing, set this field to update displayName.
    var displayName: String?
    /// An optional real name of the user.
    var realName: String?
    /// An optional preferred form of address.
    var preferredPronoun: String?
    /// An optional home location (e.g. city).
    var homeLocation: String?
    /// An optional ship cabin number.
    var roomNumber: String?
    /// An optional email address.
    var email: String?
     /// An optional short greeting/message to visitors of the profile.
    var message: String?
   /// An optional blurb about the user.
    var about: String?
}

extension UserProfileUploadData {
	init(user: User) throws {
		self.header = try UserHeader(user: user)
		self.displayName = user.displayName
		self.about = user.about
		self.email = user.email
		self.homeLocation = user.homeLocation
		self.message = user.message
		self.preferredPronoun = user.preferredPronoun
		self.realName = user.realName
		self.roomNumber = user.roomNumber
	}
}

extension UserProfileUploadData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validateStrLenOptional(displayName, min: 2, max: 50, forKey: .displayName, fieldName: "display name")
    	tester.validateStrLenOptional(realName, min: 2, max: 50, forKey: .realName, fieldName: "real name")
    	tester.validateStrLenOptional(preferredPronoun, min: 2, max: 50, forKey: .preferredPronoun, fieldName: "pronouns field")
    	tester.validateStrLenOptional(homeLocation, min: 2, max: 50, forKey: .homeLocation, fieldName: "home location")
    	tester.validateStrLenOptional(roomNumber, min: 4, max: 20, forKey: .roomNumber, fieldName: "cabin number")
    	tester.validateStrLenOptional(email, min: 4, max: 50, forKey: .email, fieldName: "email address")
    	tester.validateStrLenOptional(message, min: 4, max: 80, forKey: .message, fieldName: "message field")
    	tester.validateStrLenOptional(about, min: 4, max: 400, forKey: .about, fieldName: "about field")
	}
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
    /// The new password to set for the account.
    var newPassword: String
}

extension UserRecoveryData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(recoveryKey.count >= 6, forKey: .recoveryKey, or: "password/recovery code has a 6 character minimum")
    	usernameValidations(username: username).forEach {
    		tester.addValidationError(forKey: .username, errorString: $0)
    	}
    	tester.validate(newPassword.count >= 6, forKey: .newPassword, or: "password has a 6 character minimum length")
    	tester.validate(newPassword.count <= 50, forKey: .newPassword, or: "password has a 50 character limit")
	}
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

extension UserUsernameData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	usernameValidations(username: username).forEach {
    		tester.addValidationError(forKey: .username, errorString: $0)
    	}
	}
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

extension UserVerifyData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(verification.count >= 6 && verification.count <= 7, forKey: .verification, 
    			or: "verification code is 6 letters long (with an optional space in the middle)")
	}
}

// MARK: - Username Validation

/// Three differernt POST structs contain username fields; this fn exists to ensure they all validate the username the same way. This fn is designed to return a list
/// of validation failure strings--if it returns an empty array the username is valid.
fileprivate func usernameValidations(username: String) -> [String] {
	var errorStrings: [String] = []
	if username.count < 2 { errorStrings.append("username has a 2 character minimum") }
	if username.count > 50 { errorStrings.append("username has a 50 character limit") }
	if !username.unicodeScalars.allSatisfy({ CharacterSet.validUsernameChars.contains($0) }) {
		errorStrings.append("username can only contain alphanumeric characters plus \"\(usernameSeparatorString)\"")
	}
	if let firstChar = username.first, !(firstChar.isLetter || firstChar.isNumber) {
		errorStrings.append("username must start with a letter or number")
	}
	if let lastChar = username.unicodeScalars.last, CharacterSet.usernameSeparators.contains(lastChar) {
		errorStrings.append("Username separator chars (\(usernameSeparatorString)) can only be in the middle of a username string.")
	}
	return errorStrings
}

