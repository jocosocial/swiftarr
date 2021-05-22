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
    /// If TRUE, only mods can create/modify threads in this forum. Should be sorted to top of category list.
    var isRestricted: Bool
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
/// Returned by these methods, with `posts` set to nil.
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
/// Returned by these  methods, with `posts` populated.
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
    /// The ID of the fez's owner.
    var ownerID: UUID
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
	/// The most recent of: Creation time for the fez, time of the last post (may not exactly match post time), user add/remove, or update to fezzes' fields. 
	var lastModificationTime: Date
    /// The FezPosts in the fez discussion. Only populated for some calls; see above.
    var posts: [FezPostData]?
}

extension FezData {
	init(fez: FriendlyFez) throws {
		self.fezID = try fez.requireID()
		self.ownerID = fez.$owner.id
		self.fezType = fez.fezType
		self.title = fez.title
		self.info = fez.info
		self.startTime = fez.startTime
		self.endTime = fez.endTime
		self.location = fez.location
		self.participants = []
		self.waitingList = []
		self.postCount = 0
		self.readCount = 0
		self.lastModificationTime = fez.updatedAt ?? Date()
		self.posts = nil
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
    /// The forum's title
    var title: String
    /// The forum's creator.
	var creator: UserHeader
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether the user has favorited forum.
    var isFavorite: Bool
    /// The posts in the forum.
    var posts: [PostData]
}

extension ForumData {
    init(forum: Forum, creator: UserHeader, isFavorite: Bool, posts: [PostData]) throws {
    	guard creator.userID == forum.$creator.id else {
    		throw Abort(.internalServerError, reason: "Internal server error--Forum's creator does not match.")
    	}
    
		forumID = try forum.requireID()
		title = forum.title
		self.creator = creator
		isLocked = forum.isLocked
		self.isFavorite = isFavorite
		self.posts = posts
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
    /// Time forum was created.
    var createdAt: Date
    /// Timestamp of most recent post. Needs to be optional because admin forums may be empty.
    var lastPostAt: Date?
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether user has favorited forum.
    var isFavorite: Bool
}

extension ForumListData {
	init(forum: Forum, creator: UserHeader, postCount: Int, lastPostAt: Date?, isFavorite: Bool) throws {
    	guard creator.userID == forum.$creator.id else {
    		throw Abort(.internalServerError, reason: "Internal server error--Forum's creator does not match.")
    	}
		self.forumID = try forum.requireID()
		self.creator = creator
		self.title = forum.title
		self.postCount = postCount
		self.createdAt = forum.createdAt ?? Date()
		self.lastPostAt = lastPostAt
		self.isLocked = forum.isLocked
		self.isFavorite = isFavorite
    }

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
		if let fn = filename, fn.count > 0 {
			self.filename = fn
		}
		if let img = image, img.count > 0 {
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
    init(post: ForumPost, author: UserHeader, bookmarked: Bool, userLike: LikeType?, likeCount: Int) throws {
		postID = try post.requireID()
		createdAt = post.createdAt ?? Date()
		self.author = author
		text = post.isQuarantined ? "This post is under moderator review." : post.text
		images = post.isQuarantined ? nil : post.images
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

// FIXME: needs bookmark, userLike too?
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
    /// The seamonkeys with "laugh" reactions on the post.
    var laughs: [SeaMonkey]
    /// The seamonkeys with "like" reactions on the post.
    var likes: [SeaMonkey]
    /// The seamonkeys with "love" reactions on the post.
    var loves: [SeaMonkey]
}

/// Used to return a user's public profile contents. For viewing/editing a user's own profile, see `UserProfileData`.
///
/// Returned by: `GET /api/v3/users/ID/profile`
///
/// See `UsersController.profileHandler(_:)`.
struct ProfilePublicData: Content {
    /// Basic info abou thte user--their ID, username, displayname, and avatar image.
    var header: UserHeader

    /// An optional blurb about the user.
    var about: String
    /// An optional email address for the user.
    var message: String
    /// An optional preferred pronoun or form of address.
    var email: String
    /// An optional home location for the user.
    var homeLocation: String
    /// An optional greeting/message to visitors of the profile.
    var preferredPronoun: String
    /// An optional real world name of the user.
    var realName: String
    /// An optional cabin number for the user.
    var roomNumber: String
    /// A UserNote owned by the visiting user, about the profile's user (see `UserNote`).
    var note: String?
}

extension ProfilePublicData {
	init(user: User, note: String?) throws {
		self.header = try UserHeader(user: user)
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
    /// The ID of the twarrt to which this twarrt is a reply.
    var replyToID: Int?
    /// Whether the current user has bookmarked the twarrt.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the twarrt.
    var userLike: LikeType?
    /// The total number of `LikeType` reactions on the twarrt.
    var likeCount: Int
}

extension TwarrtData {
    init(twarrt: Twarrt, creator: UserHeader, isBookmarked: Bool, userLike: LikeType?, likeCount: Int) throws {
    	guard creator.userID == twarrt.$author.id else {
    		throw Abort(.internalServerError, reason: "Internal server error--Twarrt's creator does not match.")
    	}
		twarrtID = try twarrt.requireID()
		createdAt = twarrt.createdAt ?? Date()
		self.author = creator
		text = twarrt.text
		images = twarrt.images
		replyToID = twarrt.$replyTo.id
		self.isBookmarked = isBookmarked
		self.userLike = userLike
		self.likeCount = likeCount
    }
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
    /// The twarrt's author.
    var author: UserHeader
    /// The text of the forum post or twarrt.
    var text: String
    /// The filenames of the post/twarrt's optional images.
    var images: [String]?
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
    /// Optional verification code. If set, must be a valid code. On success, user will be created with .verified access level, consuming this code.
    /// See `/api/v3/user/verify`
    var verification: String?
}

extension UserCreateData: RCFValidatable {
    func runValidations(using decoder: ValidatingDecoder) throws {
    	let tester = try decoder.validator(keyedBy: CodingKeys.self)
    	tester.validate(username.count >= 2, forKey: .username, or: "username has a 2 character minimum")
    	tester.validate(username.count <= 50, forKey: .username, or: "username has a 50 character limit")
    	tester.validate(password.count >= 6, forKey: .password, or: "password has a 6 character minimum")
    	tester.validate(password.count <= 50, forKey: .password, or: "password has a 50 character limit")
    	var cs = CharacterSet()
    	cs.formUnion(.alphanumerics)
    	cs.formUnion(.usernameSeparators)
    	tester.validate(username.unicodeScalars.allSatisfy { cs.contains($0) }, forKey: .username, or:
    			"username can only contain alphanumeric characters plus \"\(usernameSeparatorString)\"")
    	if let firstChar = username.first, !(firstChar.isLetter || firstChar.isNumber) {
    		tester.addValidationError(forKey: .username, errorString: "username must start with a letter or number")
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

/// Used to edit the current user's profile contents. For profile data on other users, see `ProfilePublicData`.
///
/// Required by: 
/// * `POST /api/v3/user/profile`
///
/// Returned by:
/// * `GET /api/v3/user/profile`
/// * `POST /api/v3/user/profile`
///
/// See `UserController.profileHandler(_:)`, `UserController.profileUpdateHandler(_:data:)`.
struct UserProfileData: Content {
    /// The user's username. [not editable here]
    let username: String
    /// An optional blurb about the user.
    var about: String?
    /// An optional name for display alongside the username.
    var displayName: String?
    /// An optional email address.
    var email: String?
    /// An optional home location (e.g. city).
    var homeLocation: String?
    /// An optional greeting/message to visitors of the profile.
    var message: String?
    /// An optional preferred form of address.
    var preferredPronoun: String?
    /// An optional real name of the user.
    var realName: String?
    /// An optional ship cabin number.
    var roomNumber: String?
    /// Whether display of the optional fields' data should be limited to logged in users.
    var limitAccess: Bool
}

extension UserProfileData {
	init(user: User) throws {
		self.username = user.username
		self.displayName = user.displayName
		self.about = user.about
		self.email = user.email
		self.homeLocation = user.homeLocation
		self.message = user.message
		self.preferredPronoun = user.preferredPronoun
		self.realName = user.realName
		self.roomNumber = user.roomNumber
		self.limitAccess = user.limitAccess
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
    	tester.validate(username.count >= 2, forKey: .username, or: "username has a 2 character minimum")
    	tester.validate(username.count <= 50, forKey: .username, or: "username has a 50 character limit")
    	tester.validate(recoveryKey.count >= 6, forKey: .recoveryKey, or: "password/recovery code has a 6 character minimum")
    	var cs = CharacterSet()
    	cs.formUnion(.alphanumerics)
    	cs.formUnion(.usernameSeparators)
    	tester.validate(username.unicodeScalars.allSatisfy { cs.contains($0) }, forKey: .username, or:
    			"username can only contain alphanumeric characters plus \"\(usernameSeparatorString)\"")
    	if let firstChar = username.first, !(firstChar.isLetter || firstChar.isNumber) {
    		tester.addValidationError(forKey: .username, errorString: "username must start with a letter or number")
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
    	tester.validate(username.count >= 2, forKey: .username, or: "username has a 2 character minimum")
    	tester.validate(username.count <= 50, forKey: .username, or: "username has a 50 character limit")
    	var cs = CharacterSet()
    	cs.formUnion(.alphanumerics)
    	cs.formUnion(.usernameSeparators)
    	tester.validate(username.unicodeScalars.allSatisfy { cs.contains($0) }, forKey: .username, or:
    			"username can only contain alphanumeric characters plus \"\(usernameSeparatorString)\"")
    	if let firstChar = username.first, !(firstChar.isLetter || firstChar.isNumber) {
    		tester.addValidationError(forKey: .username, errorString: "username must start with a letter or number")
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
