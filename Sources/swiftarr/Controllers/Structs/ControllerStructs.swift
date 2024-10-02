import Vapor

/// Used to return a newly created sub-account's ID and username.
///
/// Returned by: `POST /api/v3/user/add`
///
/// See `UserController.addHandler(_:data:)`.
public struct AddedUserData: Content {
	/// The newly created sub-account's ID.
	let userID: UUID
	/// The newly created sub-account's username.
	let username: String
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
public struct AnnouncementData: Content {
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
		displayUntil = Settings.shared.timeZoneChanges.portTimeToDisplayTime(from.displayUntil)
		isDeleted = false
		if let deleteTime = from.deletedAt, deleteTime < Date() {
			isDeleted = true
		}
	}
}

/// Parameters for the game recommender engine. Pass these values in, get back a `BoardgameResponseData` with a
/// list of games filtered to match the criteria, and sorted based on how well they match the criteria. The sort takes into account each games'
/// overall rating from BGG, the recommended number of players (not just min and max allowed players), the average playtime,
/// and the complexity score of the game.
///
/// Sent to these methods as the JSON  request body:
/// * `GET /api/v3/boardgames/recommend`
public struct BoardgameRecommendationData: Content {
	/// How many players are going to play
	var numPlayers: Int
	/// How much time they have, in minutes
	var timeToPlay: Int
	/// If nonzero, limit results to games appropriate for this player age. Does not factor into the sort criteria. That is, if you
	/// request games appropriate for 14 years olds, games appropriate for ages 18 and older will be filtered out, but games appropriate
	/// for ages 1 and up won't be ranked any lower than games rated for 14 year olds.
	var maxAge: Int
	/// If nonzero, filter OUT games with a minAge lower than this age. Useful for filtering out games intended for young children. Does not factor into the sort criteria.
	var minAge: Int
	/// Desired complexity in the range [1...5], or zero to not consider complexity in rankings.
	var complexity: Int
}

/// Wraps an array of `BoardgameData` with info needed to paginate the result set.
///
/// Returned by:
/// * `GET /api/v3/boardgames`
public struct BoardgameResponseData: Content {
	/// Array of boardgames.
	var gameArray: [BoardgameData]
	/// Total games in result set, and the start and limit into the found set.
	var paginator: Paginator
}

/// Used to obtain a list of board games.
///
/// Each year there's a list of boardgames published that'll be brought onboard for the games library. The board game data is produced
/// by running a script that pulls game data from `http://boardgamegeek.com`'s API and merging it with the games library table.
///
/// Games in the library may not match anything in BGG's database (or we can't find a match), so all the BGG fields are optional.
///
/// Returned by:
/// * `GET /api/v3/boardgames` (inside `BoardgameResponseData`)
/// * `GET /api/v3/boardgames/:boardgameID`
/// * `GET /api/v3/boardgames/expansions/:boardgameID`
///
/// See `BoardgameController.getBoardgames(_:)`, `BoardgameController.getExpansions(_:)`.
public struct BoardgameData: Content {
	// The database ID for this game. Used to request a list of expansion sets for a game.
	var gameID: UUID
	/// Name from the JoCo boardgame list
	var gameName: String
	/// How many copies are being brought aboard.
	var numCopies: Int
	/// Some games each year are loaned to the library by specific people.
	var donatedBy: String?
	/// Any notes on the game (specific printing, wear and tear)
	var notes: String?

	/// From BoardGameGeek's API.
	var yearPublished: String?
	/// From BGG's API. Usually several paragraphs.
	var gameDescription: String?
	/// BGG's 'subdomain' value. Games can have multiple values, but often have none. BGG currently lists 8 subdomains.
	var gameTypes: [String]
	/// BGG's 'category' value. Games can have multiple values. BGG currently lists 84 categories.
	var categories: [String]
	/// BGG's 'mechanic' value. Games can have multiple values. BGG currently lists 192 mechanics.
	var mechanics: [String]

	/// From BGG's API.
	var minPlayers: Int?
	/// From BGG's API.
	var maxPlayers: Int?
	/// From BGG's API. This is the value from the "numPlayers" poll that got the highest number of "Best" votes.
	var suggestedPlayers: Int?

	/// From BGG's API. Playtime in minutes.
	var minPlayingTime: Int?
	/// From BGG's API. Playtime in minutes.
	var maxPlayingTime: Int?
	/// From BGG's API. Playtime in minutes.
	var avgPlayingTime: Int?

	/// From BGG's API. Suggested min player age in years. Min age could be determined by complexity or content.
	var minAge: Int?
	/// From BGG's API. How many BGG reviewers submitted ratings.
	var numRatings: Int?
	/// From BGG's API. Average game rating. Members can rate games with scores in the range 1...10
	var avgRating: Float?
	/// From BGG's API. Members can score a games' complexity on a scale of 1...5, where 1 is Light and 5 is Heavy.
	var complexity: Float?

	/// TRUE if this entry is an expansion for another game. Weirdly, the games library may not actually have the base game.
	/// At any rate, the base game is usually a requirement to play an expansion, and both must be checked out together.
	var isExpansion: Bool
	/// TRUE if this game has expansions that can be played with it.
	var hasExpansions: Bool
	/// TRUE if the user has favorited the game. FALSE if no one is logged in.
	var isFavorite: Bool
}

extension BoardgameData {
	init(game: Boardgame, isFavorite: Bool = false) throws {
		self.gameID = try game.requireID()
		self.gameName = game.gameName
		self.yearPublished = game.yearPublished
		self.gameDescription = game.gameDescription
		self.gameTypes = game.gameTypes
		self.categories = game.categories
		self.mechanics = game.mechanisms

		self.minPlayers = game.minPlayers
		self.maxPlayers = game.maxPlayers
		self.suggestedPlayers = game.suggestedPlayers

		self.minPlayingTime = game.minPlayingTime
		self.maxPlayingTime = game.maxPlayingTime
		self.avgPlayingTime = game.avgPlayingTime

		self.minAge = game.minAge
		self.numRatings = game.numRatings
		self.avgRating = game.avgRating
		self.complexity = game.complexity

		self.donatedBy = game.donatedBy
		self.notes = game.notes
		self.numCopies = game.numCopies

		self.isExpansion = game.$expands.id != nil
		self.hasExpansions = !game.expansions.isEmpty
		self.isFavorite = isFavorite
	}
}

/// Used to return the ID and title of a `Category`.
///
/// Returned by:
/// * `GET /api/v3/forum/categories`
/// * `GET /api/v3/forum/catgories/ID`
///
/// See `ForumController.categoriesHandler(_:)`
public struct CategoryData: Content {
	/// The ID of the category.
	var categoryID: UUID
	/// The title of the category.
	var title: String
	/// The purpose string for the category.
	var purpose: String
	/// If TRUE, the user cannot create/modify threads in this forum. Should be sorted to top of category list.
	var isRestricted: Bool
	/// if TRUE, this category is for Event Forums, and is prepopulated with forum threads for each Schedule Event.
	var isEventCategory: Bool
	/// The number of threads in this category
	var numThreads: Int32
	/// The threads in the category. Only populated for /categories/ID.
	var forumThreads: [ForumListData]?
}

extension CategoryData {
	init(_ cat: Category, restricted: Bool, forumThreads: [ForumListData]? = nil) throws {
		categoryID = try cat.requireID()
		title = cat.title
		purpose = cat.purpose
		isRestricted = restricted
		isEventCategory = cat.isEventCategory
		numThreads = cat.forumCount
		self.forumThreads = forumThreads
	}
}

/// Used to return a newly created account's ID, username and recovery key.
///
/// Returned by: `POST /api/v3/user/create`
///
/// See `UserController.createHandler(_:data:).`
public struct CreatedUserData: Content {
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
public struct CurrentUserData: Content {
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
public struct DailyThemeData: Content {
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
public struct DisabledFeature: Content {
	/// AppName and featureName act as a grid, allowing a specific feature to be disabled only in a specific app. If the appName is `all`, the server
	/// code for the feature may be causing the issue, requiring the feature be disabled for all clients.
	var appName: SwiftarrClientApp
	/// The feature to disable. Features roughly match API controller groups.
	var featureName: SwiftarrFeature
}

/// All errors returned in HTTP responses use this structure.
///
/// Some server errors (such as 404s) may not have any payload in the response body, but for any HTTP error response that has a payload, the
/// payload will have this strcture.
///
///`error` is always true, `reason` concatenates all errors into a single string, and `fieldErrors` breaks errors up by field name
/// of the request's body content, if available. Only content validation errors actaully use `fieldErrors`.
/// Field-specific validation errors are keyed by the path to the field that caused the error. Validation errors that aren't specific to an input field
/// (e.g. an error indicating that one of two fields may be empty, but not both) are all concatenated and placed into a `general` key in `fieldErrors`.
/// This means that all field errors are both in `error` (concatenated into a single string), and also in `fieldErrors` (split into fields).
///
/// - Note: If the request body has validation errors, the error response should list all validation errors at once. However, other errors that may prevent a successful
/// action will not be included. For instance, a user might try creating a Forum with empty fields. The error response will indicate that both Title and Text fields need values.
/// After fixing those issues, the user could still get an error becuase they are quarantined and not authorized to create posts.
public struct ErrorResponse: Codable, Error {
	/// Always `true` to indicate this is a non-typical JSON response.
	var error: Bool
	/// The HTTP status code.
	var status: UInt
	/// The reason for the error. Displayable to the user.
	var reason: String
	/// Optional dictionary of field errors; mostly used for input JSON validation failures. A request with JSON content that fails validation may have field-level errors here,
	/// keyed by the keypath to the fields that failed validation.
	var fieldErrors: [String: String]?
}

/// Used to obtain an event's details.
///
/// Returned by:
/// * `GET /api/v3/events`
/// * `GET /api/v3/events/favorites`
///
/// See `EventController.eventsHandler(_:)`, `EventController.favoritesHandler(_:)`.
public struct EventData: Content {
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
	/// The timezone that the ship is going to be in when the event occurs. Delivered as an abbreviation e.g. "EST".
	var timeZone: String
	/// The timezone ID that the ship is going to be in when the event occurs. Example: "America/New_York".
	var timeZoneID: String
	/// The location of the event.
	var location: String
	/// The event category.
	var eventType: String
	/// The last time data for this event was modified. Used for change management.
	var lastUpdateTime: Date
	/// The event's associated `Forum`.
	var forum: UUID?
	/// Whether user has favorited event.
	var isFavorite: Bool
	/// The performers who will be at the event.
	var performers: [PerformerHeaderData]
}

extension EventData {
	/// Makes an eventData.
	///
	/// The startTime, endTime, and timeZone are the corrected Date values for the event, given the time zone the ship was/will be in at the event start time.
	/// The Performers field will be filled in if Performers are eager loaded using `.with(\.$performers)` or similar. Else it's [].
	init(_ event: Event, isFavorite: Bool = false) throws {
		let timeZoneChanges = Settings.shared.timeZoneChanges
		eventID = try event.requireID()
		uid = event.uid
		title = event.title
		description = event.info
		self.startTime = timeZoneChanges.portTimeToDisplayTime(event.startTime)
		self.endTime = timeZoneChanges.portTimeToDisplayTime(event.endTime)
		self.timeZone = timeZoneChanges.abbrevAtTime(self.startTime)
		self.timeZoneID = timeZoneChanges.tzAtTime(self.startTime).identifier
		location = event.location
		eventType = event.eventType.label
		lastUpdateTime = event.updatedAt ?? Date()
		forum = event.$forum.id
		self.isFavorite = isFavorite
		self.performers = event.$performers.value != nil ? try event.performers.map { try PerformerHeaderData($0) } : []
	}
}

/// Used to create or update a `FriendlyFez`.
///
/// Required by:
/// * `POST /api/v3/fez/create`
/// * `POST /api/v3/fez/ID/update`
///
/// See: `FezController.createHandler(_:data:)`, `FezController.updateHandler(_:data:)`.
public struct FezContentData: Content {
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
	/// The minimum number of users needed for the fez.
	var minCapacity: Int
	/// The maximum number of users for the fez.
	var maxCapacity: Int
	/// Users to add to the fez upon creation. The creator is always added as the first user.
	var initialUsers: [UUID]
	/// If TRUE, the Fez will be created by user @moderator instead of the current user. Current user must be a mod.
	var createdByModerator: Bool?
	/// If TRUE, the Fez will be created by user @TwitarrTeam instead of the current user. Current user must be a TT member.
	var createdByTwitarrTeam: Bool?
}

extension FezContentData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(title.count >= 2, forKey: .title, or: "title field has a 2 character minimum")
		tester.validate(title.count <= 100, forKey: .title, or: "title field has a 100 character limit")
		if ![.closed, .open].contains(fezType) {
			tester.validate(info.count >= 2, forKey: .info, or: "info field has a 2 character minimum")
			tester.validate(
				info.count <= 2048,
				forKey: .info,
				or: "info field length of \(info.count) is over the 2048 character limit"
			)
			if let loc = location {
				tester.validate(loc.count >= 3, forKey: .location, or: "location field has a 3 character minimum")
			}
		}

		if let startTime = startTime {
			guard let endTime = endTime else {
				throw Abort(.badRequest, reason: "if startTime is defined so must endTime")
			}
			let timeInterval = endTime.timeIntervalSince(startTime)
			guard timeInterval <= 86400 else {
				throw Abort(.badRequest, reason: "endTime can be no more than 24 hours after startTime")
			}
		}
	}
}

/// Used to return data on a group of `FriendlyFez` objects.
///
///
public struct FezListData: Content {
	/// Pagination into the results set.
	var paginator: Paginator
	///The fezzes in the result set.
	var fezzes: [FezData]
}

/// Used to return a `FriendlyFez`'s data.
///
/// Returned by these methods, with `members` set to nil.
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
/// * `POST /api/v3/fez/create`
/// * `POST /api/v3/fez/ID/post`
/// * `POST /api/v3/fex/ID/post/ID/delete`

/// See `FezController.createHandler(_:data:)`, `FezController.joinHandler(_:)`,
/// `FezController.unjoinHandler(_:)`, `FezController.joinedHandler(_:)`
/// `FezController.openhandler(_:)`, `FezController.ownerHandler(_:)`,
/// `FezController.userAddHandler(_:)`, `FezController.userRemoveHandler(_:)`,
/// `FezController.cancelHandler(_:)`.
public struct FezData: Content, ResponseEncodable {
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
	/// The ending time of the fez. If startTime specified, no more than 24 hours after
	/// the startTime since per Chall that makes iCal export get weird.
	var endTime: Date?
	/// The 3 letter abbreviation for the active time zone at the time and place where the fez is happening.
	var timeZone: String?
	/// The timezone ID that the ship is going to be in when the fez occurs. Example: "America/New_York".
	var timeZoneID: String?
	/// The location for the fez.
	var location: String?
	/// How many users are currently members of the fez. Can be larger than maxParticipants; which indicates a waitlist.
	var participantCount: Int
	/// The min number of people for the activity. Set by the host. Fezzes may?? auto-cancel if the minimum participant count isn't met when the fez is scheduled to start.
	var minParticipants: Int
	/// The max number of people for the activity. Set by the host.
	var maxParticipants: Int
	/// TRUE if the fez has been cancelled by the owner. Cancelled fezzes should display CANCELLED so users know not to show up, but cancelled fezzes are not deleted.
	var cancelled: Bool
	/// The most recent of: Creation time for the fez, time of the last post (may not exactly match post time), user add/remove, or update to fezzes' fields.
	var lastModificationTime: Date

	/// FezData.MembersOnlyData returns data only available to participants in a Fez.
	public struct MembersOnlyData: Content, ResponseEncodable {
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
		/// Paginates the array in posts--gives the start and limit of the returned posts array relative to all the posts in the thread.
		var paginator: Paginator?
		/// The FezPosts in the fez discussion. Methods that return arrays of Fezzes, or that add or remove users, do not populate this field (it will be nil).
		var posts: [FezPostData]?
		/// Whether user has muted the fez.
		var isMuted: Bool
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
		self.startTime =
			fez.startTime == nil ? nil : Settings.shared.timeZoneChanges.portTimeToDisplayTime(fez.startTime)
		self.endTime = fez.endTime == nil ? nil : Settings.shared.timeZoneChanges.portTimeToDisplayTime(fez.endTime)
		self.timeZone = self.startTime == nil ? nil : Settings.shared.timeZoneChanges.abbrevAtTime(self.startTime)
		self.timeZoneID =
			self.startTime == nil ? nil : Settings.shared.timeZoneChanges.tzAtTime(self.startTime).identifier
		self.location =
			fez.moderationStatus.showsContent() ? fez.location : "Fez Location field is under moderator review"
		self.lastModificationTime = fez.updatedAt ?? Date()
		self.participantCount = fez.participantArray.count
		self.minParticipants = fez.minCapacity
		self.maxParticipants = fez.maxCapacity
		self.members = nil
		self.cancelled = fez.cancelled
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
public struct FezPostData: Content {
	/// The ID of the fez post.
	var postID: Int
	/// The fez post's author.
	var author: UserHeader
	/// The text content of the fez post.
	var text: String
	/// The time the post was submitted.
	var timestamp: Date
	/// The image content of the fez post.
	var image: String?
}

extension FezPostData {
	init(post: FezPost, author: UserHeader, overrideQuarantine: Bool = false) throws {
		guard author.userID == post.$author.id else {
			throw Abort(.internalServerError, reason: "Internal server error--Post's author does not match.")
		}
		self.postID = try post.requireID()
		self.author = author
		self.text =
			post.moderationStatus.showsContent() || overrideQuarantine ? post.text : "Post is under moderator review."
		self.timestamp = post.createdAt ?? post.updatedAt ?? Date()
		self.image = post.moderationStatus.showsContent() || overrideQuarantine ? post.image : nil
	}
}

/// Used to create a new `Forum`.
///
/// Required by: `POST /api/v3/forum/categories/ID/create`
///
/// See `ForumController.forumCreateHandler(_:data:)`.
public struct ForumCreateData: Content {
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
public struct ForumData: Content {
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
	/// Whether the user has muted the forum.
	var isMuted: Bool
	/// The paginator contains the total number of posts in the forum, and the start and limit of the requested subset in `posts`.
	var paginator: Paginator
	/// Posts in the forum.
	var posts: [PostData]
	/// If this forum is for an Event on the schedule, the ID of the event.
	var eventID: UUID?
	/// If this forum is pinned or not.
	var isPinned: Bool?
}

extension ForumData {
	init(
		forum: Forum,
		creator: UserHeader,
		isFavorite: Bool,
		isMuted: Bool,
		posts: [PostData],
		pager: Paginator,
		event: Event? = nil
	) throws {
		guard creator.userID == forum.$creator.id else {
			throw Abort(.internalServerError, reason: "Internal server error--Forum's creator does not match.")
		}
		forumID = try forum.requireID()
		categoryID = forum.$category.id
		title = forum.moderationStatus.showsContent() ? forum.title : "Forum Title is under moderator review"
		self.creator = creator
		isLocked = forum.moderationStatus == .locked
		self.isFavorite = isFavorite
		self.isMuted = isMuted
		self.posts = posts
		self.paginator = pager
		if let event = event, event.id != nil {
			self.eventID = event.id
		}
		self.isPinned = forum.pinned
	}
}

/// Used to return the ID, title and status of a `Forum`.
///
/// Returned by:
/// * `GET /api/v3/forum/categories/ID`
/// * `GET /api/v3/forum/owner`
/// * `GET /api/v3/user/forums`
/// * `GET /api/v3/forum/favorites`
///
/// See `ForumController.categoryForumsHandler(_:)`, `ForumController.ownerHandler(_:)`,
/// `ForumController.forumMatchHandler(_:)`, `ForumController.favoritesHandler(_:).
public struct ForumListData: Content {
	/// The forum's ID.
	var forumID: UUID
	/// The ID of the forum's containing Category..
	var categoryID: UUID
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
	/// Whether user has muted the forum.
	var isMuted: Bool
	/// If this forum is for an Event on the schedule, the start time of the event.
	var eventTime: Date?
	/// If this forum is for an Event on the schedule, the timezone that the ship is going to be in when the event occurs. Delivered as an abbreviation e.g. "EST".
	var timeZone: String?
	/// If this forum is for an Event on the schedule, the timezone ID that the ship is going to be in when the event occurs. Example: "America/New_York".
	var timeZoneID: String?
	/// If this forum is for an Event on the schedule, the ID of the event.
	var eventID: UUID?
	/// If this forum is pinned or not.
	var isPinned: Bool?
}

extension ForumListData {
	init(
		forum: Forum,
		creator: UserHeader,
		postCount: Int,
		readCount: Int,
		lastPostAt: Date?,
		lastPoster: UserHeader?,
		isFavorite: Bool,
		isMuted: Bool,
		event: Event?
	) throws {
		guard creator.userID == forum.$creator.id else {
			throw Abort(.internalServerError, reason: "Internal server error--Forum's creator does not match.")
		}
		self.forumID = try forum.requireID()
		self.categoryID = forum.$category.id
		self.creator = creator
		self.title = forum.moderationStatus.showsContent() ? forum.title : "Forum Title is under moderator review"
		self.postCount = postCount
		self.readCount = readCount
		self.createdAt = forum.createdAt ?? Date()
		self.lastPostAt = lastPostAt
		self.lastPoster = lastPoster
		self.isLocked = forum.moderationStatus == .locked
		self.isFavorite = isFavorite
		self.isMuted = isMuted
		self.isPinned = forum.pinned

		if let event = event, event.id != nil {
			let timeZoneChanges = Settings.shared.timeZoneChanges
			self.eventTime = timeZoneChanges.portTimeToDisplayTime(event.startTime)
			self.timeZone = timeZoneChanges.abbrevAtTime(self.eventTime)
			self.timeZoneID = timeZoneChanges.tzAtTime(self.eventTime).identifier
			self.eventID = event.id
		}
	}
}

/// Used to return a (partial) list of forums along with the number of forums in the found set. Similar to CategoryData, but the
/// forums need not be from the same category. Instead, this returns forums that match a common attribute acoss all categores.
///
/// Returned by:
/// * `GET /api/v3/forum/favorites`
/// * `GET /api/v3/forum/owner`
///
/// See `ForumController.categoriesHandler(_:)`
public struct ForumSearchData: Content {
	/// Paginates the list of forum threads. `paginator.total` is the total number of forums that match the request parameters.
	/// `limit` and `start` define a slice of the total results set being returned in `forumThreads`.
	var paginator: Paginator
	/// A slice of the set of forum threads that match the request parameters.
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
public struct ImageUploadData: Content {
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

/// Wraps an array of `KaraokeSongData` with information for pagination.
/// `KaraokeSongData` returns data about a single song.
///
/// Returned by: `GET /api/v3/karaoke`
/// See `KaraokeController.getKaraokeSongs()`.
public struct KaraokeSongResponseData: Content {
	/// How many songs are in the found set. The found set is sorted by Artist, then by Song Title. The found set may often be larger than `songs.count`.
	var totalSongs: Int
	/// The offset within the found set to begin returning results.
	var start: Int
	/// How many results to return.
	var limit: Int
	/// The array of songs that match
	var songs: [KaraokeSongData]
}

/// Returns information about a song in the Karaoke Song Library.
///
/// Returned by: `GET /api/v3/karaoke/:song_id`
/// Incorporated into: `KaraokeSongResponseData`
public struct KaraokeSongData: Content {
	/// The database ID of the song. Used to mark favorite songs and to log song performances.
	var songID: UUID
	/// The artist or band that produced the song.
	var artist: String
	/// The title of the song
	var songName: String
	/// If TRUE, this song is a MIDI track.
	var isMidi: Bool
	/// If TRUE, this track is the regular released version of the song, post-processed with voice removal software.
	/// If FALSE, the track is (assumedly) the karaoke mix of the track.
	var isVoiceReduced: Bool
	/// TRUE if this user has favorited this song. Always FALSE if not logged in.
	var isFavorite: Bool
	/// An array of performances of this song in the Karaoke Lounge on boat this year. [] if the song hasn't been performed.
	var performances: [KaraokePerformedSongsData]
}

extension KaraokeSongData {
	init(with song: KaraokeSong, isFavorite: Bool) throws {
		songID = try song.requireID()
		artist = song.artist
		songName = song.title
		isMidi = song.midi
		isVoiceReduced = song.voiceRemoved
		self.isFavorite = isFavorite
		performances = []
		if song.$sungBy.value != nil {
			performances = song.sungBy.map {
				KaraokePerformedSongsData(
					artist: song.artist,
					songName: song.title,
					performers: $0.performers,
					time: $0.createdAt ?? Date()
				)
			}
		}
	}
}

/// Returns information about songs that have been performed in the Karaoke Lounge onboard.
///
/// Returned by: `GET /api/v3/karaoke/performance`
/// Incorporated into: `KaraokeSongData`, which itself is incorporated into `KaraokeSongResponseData`
public struct KaraokePerformedSongsData: Content {
	/// The artist that originally performed this song.
	var artist: String
	/// The title of the song.
	var songName: String
	/// The person or people aboard the boat who performed this song in the Karaoke Lounge.
	var performers: String
	/// The time the performance was logged -- this is usually the time the song was performed.
	var time: Date
}

/// Returns information about songs that have been performed in the Karaoke Lounge onboard.
///
/// Returned by: `GET /api/v3/karaoke/performance`
/// Incorporated into: `KaraokeSongData`, which itself is incorporated into `KaraokeSongResponseData
public struct KaraokePerformedSongsResult: Content {
	/// The returned songs data..
	var songs: [KaraokePerformedSongsData]
	/// Pagination info.
	var paginator: Paginator
}

/// Used to obtain the user's current list of alert or mute keywords.
///
/// Returned by:
/// * `GET /api/v3/user/alertwords`
/// * `POST /api/v3/user/alertwords/add/STRING`
/// * `POST /api/v3/user/alertwords/remove/STRING`
/// * `GET /api/v3/user/mutewords`
/// * `POST /api/v3/user/mutewords/add/STRING`
/// * `POST /api/v3/user/mutewords/remove/STRING`
///
/// See `UserController.alertwordsHandler(_:)`, `UserController.alertwordsAddHandler(_:)`,
/// `UserController.alertwordsRemoveHandler(_:)`.
public struct KeywordData: Content {
	/// The keywords.
	var keywords: [String]
}

/// Used to return a list of completed Micro Karaoke songs, that is, finished videos the user can watch.
///
/// Returned by:
/// * `GET /api/v3/karaoke/mk/songlist`
///
/// See `UsersController.headerHandler(_:)`, `ClientController.userHeadersHandler(_:)`.
public struct MicroKaraokeCompletedSong: Content {
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	// The song title, as it'd appear in karaoke metadata
	var songName: String
	/// The artist, as they'd appear in karaoke metadata
	var artistName: String
	/// How many song slots this song has. NOT how many are currently filled. This number includes pre-filled 'filler' slots for instrumental sections.
	var totalSnippetSlots: Int
	/// Always TRUE unless the user is a mod, in which case will be FALSE for songs that have all the necessary clips recorded but require mod approval to publish.
	var modApproved: Bool
	/// When the song's clips were last modified. Usually the time the final snippet gets uploaded (although 'final' means '30th out of 30'
	/// and not 'the one at the end of the song'). However, clips can get deleted via moderation, causing the server to re-issue an offer
	/// for the deleted clip, which may change the completion time. NIL if song isn't complete
	var completionTime: Date?
	/// TRUE if the current user contributed to the song
	var userContributed: Bool
}

extension MicroKaraokeCompletedSong {
	init(from song: MKSong, userContributed: Bool) throws {
		songID = try song.requireID()
		songName = song.songName
		artistName = song.artistName
		totalSnippetSlots = song.totalSnippets
		completionTime = song.isComplete ? (song.updatedAt ?? Date()) : nil
		modApproved = song.modApproved
		self.userContributed = userContributed
	}
}

/// Used to upload a Micro Karaoke video. The offerID comes from the server when it offers a song clip.
///
/// Used by:
/// * `POST /api/v3/karaoke/mk/recording`
///
public struct MicroKaraokeRecordingData: Content {
	/// The offer from the server that this upload is fulfilling. Basically the reservation the server gives the client for a song clip.
	var offerID: UUID
	/// The uploaded video; usually a .mp4
	var videoData: Data
}

public struct MicroKaraokeSnippetModeration: Content {
	///	The ID of this offer, or completed snippet
	var snippetID: UUID
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	/// The index into the Edit Decision List for this snippet. Not that there's an actual EDL.
	var snippetIndex: Int
	/// The user who has the reservation on this snippet.
	var user: UserHeader
	/// The location of the uploaded video for this snippet. NIL if this snippet is an open offer for some user
	var videoURL: String?
}

extension MicroKaraokeSnippetModeration {
	/// Author must be the UserHeader for the snippet's author.
	init(from snippet: MKSnippet, by author: UserHeader) throws {
		snippetID = try snippet.requireID()
		songID = snippet.$song.id
		snippetIndex = snippet.songSnippetIndex
		self.user = author
		videoURL = snippet.mediaURL
	}
}

/// When a user starts the Micro Karaoke flow to sing and record part of a song, the server reserves a song slot for that user and returns into
/// about their reservation, including the lyrics they should sing, what song it's part of, and URLs for the vocal and no-vocal song clipe.
///
/// Returned by:
/// * `POST /api/v3/karaoke/mk/offer`
///
public struct MicroKaraokeOfferPacket: Content {
	///	The ID of this offer. Offers are good for 30 minutes (or until fulfilled with a snippet upload), and a user may only
	/// have 1 open offer at a time. If a user re-requests while the offser is open, they should get the same offer response.
	/// This prevents users shopping for the lyric they want to sing.
	var offerID: UUID
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	/// The song title, as it'd appear in karaoke metadata
	var songName: String
	/// The artist, as they'd appear in karaoke metadata
	var artistName: String
	/// Song tempo. May not be exact; used for the timing of the countdown prompt before recording starts.
	var bpm: Int
	/// TRUE if all the clips for this song must be recorded in portrait mode. FALSE if they all need to be landscape.
	var portraitMode: Bool
	/// Which song snippet is being offered (songs are divided into 30-50 snippets when configured for use on Swiftarr)
	var snippetIndex: Int
	/// The lyrics the user is supposed to sing. Generally 1-2 lines. NOT the entire lyrics for the song.
	var lyrics: String
	/// An URL that points to a .mp3 file containing ~6 seconds of the original song
	/// This clip will have the artist singing the lyrics of 1-2 lines of the song, for the user to listen to before recording.
	var originalSnippetSoundURL: String
	/// This is a karaoke backing snippet to play while recording. It will be the same part of the song as `originalSnippetSoundURL`
	/// but MAY NOT quite be the same duration (karaoke versions of songs are sometimes faster or slower tempo then their originals).
	/// As a karaoke track, this snippet won't have main vocals, but it also could have slightly diffeent instruments/sounds.
	var karaokeSnippetSoundURL: String
	/// The time that this offer expires. If no upload has happened by this time, the user will need to request a new snippet offer,
	/// which will likely be for a different part of the song, or even a different song altogether.
	var offerExpirationTime: Date
}

extension MicroKaraokeOfferPacket {
	init(from snippet: MKSnippet, song: MKSong, snippetDirectory: URL, lyrics: String) throws {
		offerID = try snippet.requireID()
		songID = snippet.$song.id
		songName = song.songName
		artistName = song.artistName
		bpm = song.bpm
		portraitMode = song.isPortrait
		snippetIndex = snippet.songSnippetIndex
		self.lyrics = lyrics
		originalSnippetSoundURL = snippetDirectory.appendingPathComponent("listen.mp3").absoluteString
		karaokeSnippetSoundURL = snippetDirectory.appendingPathComponent("record.mp3").absoluteString
		offerExpirationTime = snippet.deletedAt ?? Date().addingTimeInterval(30 * 60)
	}
}

public struct MicroKaraokeSongManifest: Content {
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	/// TRUE if all the clips for this song must be recorded in portrait mode. FALSE if they all need to be landscape.
	var portraitMode: Bool
	/// The video snippets that make up the song. Some snippets may be 'filler', such as for a song's instrumental section.
	var snippetVideoURLs: [URL]
	/// How long each snippet should be, in seconds.
	var snippetDurations: [Double]
	/// The karaoke audio for the song
	var karaokeMusicTrack: URL
}

extension MicroKaraokeSongManifest {
	init(from snippets: [MKSnippet], song: MKSong, info: SongInfoJSON, karaokeMusicTrack: URL) throws {
		guard let first = snippets.first else {
			throw Abort(
				.internalServerError,
				reason: "No song clips found for supposedly completed micro karaoke song."
			)
		}
		songID = first.$song.id
		portraitMode = song.isPortrait
		snippetVideoURLs = try snippets.map {
			guard let mediaURL = $0.mediaURL, let url = URL(string: mediaURL) else {
				throw Abort(.internalServerError, reason: "Could not make URL out of video clip file.")
			}
			return url
		}
		self.karaokeMusicTrack = karaokeMusicTrack
		self.snippetDurations = info.durations
	}
}

/// Used to create a `UserNote` when viewing a user's profile. Also used to create a Karaoke song log entry.
///
/// Required by:
/// * `/api/v3/users/:userID/note`
/// * `/api/v3/karaoke/:songID/logperformance`
///
/// See `UsersController.noteCreateHandler(_:data:)`.
public struct NoteCreateData: Content {
	/// The text of the note.
	var note: String
}

extension NoteCreateData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(note.count > 0, forKey: .note, or: "post text cannot be empty.")
		tester.validate(
			note.count < 1000,
			forKey: .note,
			or: "post length of \(note.count) is over the 1000 character limit"
		)
		let lines = note.replacingOccurrences(of: "\r\n", with: "\r").components(separatedBy: .newlines).count
		tester.validate(lines <= 25, forKey: .note, or: "posts are limited to 25 lines of text")
	}
}

/// Used to obtain the contents of a `UserNote` for display in a non-profile-viewing context.
///
/// Returned by:
/// * `GET /api/v3/user/notes`
/// * `GET /api/v3/users/ID/note`
/// * `POST /api/v3/user/note`
///
/// See `UserController.notesHandler(_:)`, `UserController.noteHandler(_:data:)`.
public struct NoteData: Content {
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

/// Composes into other structs to add pagination.
///
/// Generally this will be added to a top-level struct along with an array of some result type, like this:
///
/// ```
/// 	struct SomeCollectionData: Content {
/// 		var paginator: Paginator
/// 		var collection: [CollectionElementType]
/// 	}
/// ```
/// The Paginator lets you page through results, showing the total number of pages and the current page.
/// The outer-level struct should document the sort ordering for the returned collection; the first element
/// in the sorted collection is returned in the first result element when start = 0.
///
/// In many cases the size of the returned array will be smaller than limit, and not only at the end of the results.
/// In several cases the results may be filtered after the database query returns. The next 'page' of results should
/// be calculated with `start + limit`, not with `start + collection.count`.
public struct Paginator: Content {
	/// The total number of items returnable by the request.
	var total: Int
	/// The index number of the first item in the collection array, relative to the overall returnable results.
	var start: Int
	/// The number of results requested. The collection array could be smaller than this number.
	var limit: Int
}

/// This simple generic lets us declare route result types as `Paginated<ContentType>`, where ContentType is 
/// an array of some Content struct (probably found in this file). This simplifies writing paginated reults as we don't 
/// need to create a separate struct just to hold the paginator, but it may make the structs more opaque, especially to
/// those that don't know Swift. Part of the idea of this file was to make it easy for developers to understand the JSON
/// that would be emitted by these structs.
public struct Paginated<ResultClass>: Content where ResultClass: Content {
	var items: [ResultClass]
	var paginator: Paginator
}

/// Returns info about a single Performer. This header information is similar to the UserHeader structure, containing just enough
/// info to build a title card for a performer.
///
/// This structure is also used to break the recusion cycle where a PerformerData contains a list of Events, and the
/// Events contain lists of the Performers that will be there. In this case, the Event has an array of PerformerHeaderData instead of PerformerData.
///
/// Incorporated into `PerformerData`
/// Incorporated into `EventData`
public struct PerformerHeaderData: Content {
	/// Database ID of hte performer. Used to get full performer info via `/api/v3/performer/<id>`
	var id: UUID?
	/// Name of the performer
	var name: String
	/// Photo ID, accessible through `/api/v3/image/[full|thumb]/<photo>` methods in the `ImageController`.
	var photo: String?
	/// TRUE if the performer is on JoCo's list of featured guests. FALSE if this is a shadow event organizer.
	var isOfficialPerformer: Bool
}

extension PerformerHeaderData {
	init(_ performer: Performer) throws {
		id = try performer.requireID()
		name = performer.name
		photo = performer.photo
		isOfficialPerformer = performer.officialPerformer
	}

	init() {
		id = nil
		name = ""
		photo = nil
		isOfficialPerformer = false
	}
}

/// Returns info about a single perfomer. Most fields are optional, and the array fields may be empty, although they shouldn't be under normal conditions.
///
/// Returned by: `GET /api/v3/performer/self`
/// Returned by: `GET /api/v3/performer/:performer_id`
public struct PerformerData: Content {
	/// ID, name, photo -- used to create a title card
	var header: PerformerHeaderData
	/// For Shadow Event Organizers, the Performer links to their User, but don't use the user's pronoun field when referring to them as a Performer.
	var pronouns: String?
	/// Bio may contain Markdown.
	var bio: String?
	/// Bandname, NGO, university, Podcast name, etc. Should only be filled if the org is relevant to the performer's event.
	var organization: String?
	/// Should only be non-nil if it's a title that's relevant to the performer's event. Hopefully won't contain 'Mr./Mrs."
	var title: String?
	/// Should be a fully-qualified URL.
	var website: String?
	/// Should be a fully-qualified URL.
	var facebookURL: String?
	/// Should be a fully-qualified URL.
	var xURL: String?
	/// Should be a fully-qualified URL.
	var instagramURL: String?
	/// Should be a fully-qualified URL.
	var youtubeURL: String?
	/// Full 4-digit years, ascending order-- like this: [2011, 2012, 2022]
	var yearsAttended: [Int]
	/// The events this performer is going to be performing at.
	var events: [EventData]
	/// The user who  created this Performer. Only applies to Shadow Event organizers, and is only returned if the requester is a Moderator or higher.
	/// Although we track the User who created a Performer model for their shadow event for moderation purposes, the User behind the Performer
	/// shouldn't be shown to everyone.
	var user: UserHeader?
}

extension PerformerData {
	init(_ performer: Performer, favoriteEventIDs: Set<UUID>) throws {
		header = try .init(performer)
		pronouns = performer.pronouns
		bio = performer.bio
		organization = performer.organization
		title = performer.title
		website = performer.website
		facebookURL = performer.facebookURL
		xURL = performer.xURL
		instagramURL = performer.instagramURL
		youtubeURL = performer.youtubeURL
		self.events = try performer.events.map { try EventData($0, isFavorite: favoriteEventIDs.contains($0.requireID())) }
		self.yearsAttended = performer.yearsAttended
	}

	// Empty performerData for users that don't have a Performer object
	init() {
		header = .init()
		events = []
		yearsAttended = []
	}
}

/// Wraps up a list of performers with pagination info.
///
/// Returned by:`GET /api/v3/performer/official`
/// Returned by:`GET /api/v3/performer/shadow`
public struct PerformerResponseData: Content {
	/// The requested performers
	var performers: [PerformerHeaderData]
	/// Pagination info.
	var paginator: Paginator
}

/// Used to create and update Performer models.
///
/// Used by: `POST /api/v3/performer/forEvent/:event_id`
/// Used by: `POST /api/v3/performer/official/add`
public struct PerformerUploadData: Content {
	/// If this is an existing performer that is being updated. Not required for shadow event organizers; we can find them by userID.
	var performerID: UUID?
	/// The name of the performer. Required.
	var name: String
	var pronouns: String?
	/// Bio can contain Markdown.
	var bio: String?
	/// New photo data if we're updating it, or the name of an existing photo on the server.
	var photo: ImageUploadData
	/// TRUE if this is an official performer, FALSE if it's a shadow event organizer. Note that this struct can't link a Performer with a User, so can't be
	/// used by admin/mods to create Shadow Event Organizers. The idea is that they should create their records themselves, but mods may have to edit them.
	var isOfficialPerformer: Bool
	var organization: String?
	var title: String?
	var yearsAttended: [Int]
	/// Social media URLs. Should be actual URLs we put into an HREF.
	var website: String?
	/// Social media URLs. Should be actual URLs we put into an HREF.
	var facebookURL: String?
	/// Social media URLs. Should be actual URLs we put into an HREF.
	var xURL: String?
	/// Social media URLs. Should be actual URLs we put into an HREF.
	var instagramURL: String?
	/// Social media URLs. Should be actual URLs we put into an HREF.
	var youtubeURL: String?
	/// UIDs of events where this performer is scheduled to appear.
	var eventUIDs: [String]
}

extension PerformerUploadData {
	/// Used to add Performer data to a UserSaveRestoreData for user archiving
	init(_ performer: Performer) throws {
		performerID = try performer.requireID()
		name = performer.name
		pronouns = performer.pronouns
		bio = performer.bio
		photo = ImageUploadData(filename: performer.photo)
		isOfficialPerformer = performer.officialPerformer
		organization = performer.organization
		title = performer.title
		yearsAttended = performer.yearsAttended
		website = performer.website
		facebookURL = performer.facebookURL
		xURL = performer.xURL
		instagramURL = performer.instagramURL
		youtubeURL = performer.youtubeURL
		if performer.$events.value != nil {
			eventUIDs = performer.events.map { $0.uid }
		}
		else {
			eventUIDs = []
		}
	}
}

/// Returns info about a single Photo from the Photostream.
///
/// Incorporated into `PhotostreamListData`, which is returned by: `GET /api/v3/photostream`
struct PhotostreamImageData: Content {
	/// The ID of the photostream record (NOT the id of the image)..
	var postID: Int
	/// The time the image was taken--not necessarily the time the image was uploaded..
	var createdAt: Date
	/// The post's author.
	var author: UserHeader
	/// The filename of the image.
	var image: String
	/// The schedule event this image was tagged with, if any. Stream photos will be tagged with either an event or a location.
	var event: EventData?
	/// The boat location this image was tagged with, if any. Value will be a raw string from  `PhotoStreamBoatLocation` or nil.  Stream photos will be tagged with either an event or a location.
	var location: String?
}

extension PhotostreamImageData {
	init(streamPhoto: StreamPhoto, author: UserHeader) throws {
		self.postID = try streamPhoto.requireID()
		self.createdAt = streamPhoto.captureTime
		self.image = streamPhoto.image
		self.author = author
		if let event = streamPhoto.atEvent {
			self.event = try EventData(event)
		}
		else if let location = streamPhoto.boatLocation?.rawValue {
			self.location = location
		}
		else {
			self.location = PhotoStreamBoatLocation.onBoat.rawValue
		}
	}
}

/// Returns paginated data on photos in the photo stream. Non-Mods should only have access to the most recent photos, with no pagination.
/// However: `/api/v3/photostream` returns one of thse objects even for non-mod users--it just returns 30 photos and sets `paginator.total` to 30.
///
/// Returned by: `GET /api/v3/photostream`
struct PhotostreamListData: Content {
	var photos: [PhotostreamImageData]
	var paginator: Paginator
}

/// Returns information on available tags to use when tagging a photo to be uploaded to the photostream. A photo may be tagged with an event or with a generic
/// ship location. Calling `api/v3/photostream/placenames` fills the `events` parameter with information about events that are currently happening. When
/// a photo is uploaded, its tag is validated, and validation will fail if the tagged event has ended.
///
/// Returned by: `GET /api/v3/photostream`
struct PhotostreamLocationData: Content {
	var events: [EventData]
	var locations: [String]
}

/// Uploads a photo to the photostream. Either the eventID or the locationName must be set.
///
/// Sent in request body to: `POST /api/v3/photostream/upload`.
struct PhotostreamUploadData: Content {
	/// The image data.
	var image: Data
	/// The time the image was taken--not necessarily the time the image was uploaded..
	var createdAt: Date
	/// The Schedule Event the photo was taken at, if any. ID must refer to an event that is currently happening--that is, an event that `/api/v3/photostream/placenames` returns.
	/// Either the eventID or locationName field must be non-nil.
	var eventID: UUID?
	/// Where the picture was taken. Valid values come from `/api/v3/photostream/placenames` and are transient. Names include titles of events currently happening..
	var locationName: String?
}

/// Used to create or update a `ForumPost`, `Twarrt`, or `FezPost`.
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
public struct PostContentData: Content {
	/// The new text of the forum post.
	var text: String
	/// An array of up to 4 images (1 when used in a Fez post). Each image can specify either new image data or an existing image filename.
	/// For new posts, images will generally contain all new image data. When editing existing posts, images may contain a mix of new and existing images.
	/// Reorder ImageUploadDatas to change presentation order. Set images to [] to remove images attached to post when editing.
	var images: [ImageUploadData]
	/// If the poster has moderator privileges and this field is TRUE, this post will be authored by 'moderator' instead of the author.
	/// Set this to FALSE unless the user is a moderator who specifically chooses this option.
	var postAsModerator: Bool = false
	/// If the poster has moderator privileges and this field is TRUE, this post will be authored by 'TwitarrTeam' instead of the author.
	/// Set this to FALSE unless the user is a moderator who specifically chooses this option.
	var postAsTwitarrTeam: Bool = false
}

extension PostContentData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(text.count > 0, forKey: .text, or: "post text cannot be empty.")
		tester.validate(
			text.count < 2048,
			forKey: .text,
			or: "post length of \(text.count) is over the 2048 character limit"
		)
		tester.validate(images.count < 5, forKey: .images, or: "posts are limited to 4 image attachments")
		let lines = text.replacingOccurrences(of: "\r\n", with: "\r").components(separatedBy: .newlines).count
		tester.validate(lines <= 25, forKey: .text, or: "posts are limited to 25 lines of text")
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
public struct PostData: Content {
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
	/// Whether the post has been pinned to the forum.
	var isPinned: Bool?
}

extension PostData {
	init(
		post: ForumPost,
		author: UserHeader,
		bookmarked: Bool,
		userLike: LikeType?,
		likeCount: Int,
		overrideQuarantine: Bool = false
	) throws {
		postID = try post.requireID()
		createdAt = post.createdAt ?? Date()
		self.author = author
		text = post.isQuarantined && !overrideQuarantine ? "This post is under moderator review." : post.text
		images = post.isQuarantined && !overrideQuarantine ? nil : post.images
		isBookmarked = bookmarked
		self.userLike = userLike
		self.likeCount = likeCount
		self.isPinned = post.pinned
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
public struct PostSearchData: Content {
	/// The search query used to create these results.
	var queryString: String
	/// The posts in the forum.
	var posts: [PostData]
	/// Pagination into the results set. Because `/forum/post/search` filters the result set after the db query, `posts.count` could be less than `paginator.limit`
	/// even if we're not at the end of the results. To get the next 'page' of results, be sure to add `limit` to `start`; don't add`posts.count`.
	var paginator: Paginator
}

/// Used to return a `ForumPost`'s data with full user `LikeType` info.
///
/// Returned by: `GET /api/v3/forum/post/ID`
///
/// See `ForumController.postHandler(_:)`.
public struct PostDetailData: Content {
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
	/// The users with "laugh" reactions on the post.
	var laughs: [UserHeader]
	/// The users with "like" reactions on the post.
	var likes: [UserHeader]
	/// The users with "love" reactions on the post.
	var loves: [UserHeader]
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
public struct ProfilePublicData: Content {
	/// Basic info about the user--their ID, username, displayname, and avatar image.
	var header: UserHeader
	/// An optional real world name of the user.
	var realName: String
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
	/// An optional dinner team assignemnt.
	var dinnerTeam: DinnerTeam?
	/// A UserNote owned by the visiting user, about the profile's user (see `UserNote`).
	var note: String?
	/// Whether the requesting user has favorited this user.
	var isFavorite: Bool
}

extension ProfilePublicData {
	init(user: User, note: String?, requesterAccessLevel: UserAccessLevel, requesterHasFavorite: Bool) throws {
		self.header = try UserHeader(user: user)
		self.isFavorite = requesterHasFavorite
		if !user.moderationStatus.showsContent() && !requesterAccessLevel.hasAccess(.moderator) {
			self.header.displayName = nil
			self.header.userImage = nil
			self.about = ""
			self.email = ""
			self.homeLocation = ""
			self.message = "This profile is under moderator review"
			self.realName = ""
			self.roomNumber = ""
			self.dinnerTeam = nil
			self.note = note
		}
		else if requesterAccessLevel == .banned {
			self.about = ""
			self.email = ""
			self.homeLocation = ""
			self.message = "You must be logged in to view this user's Profile details."
			self.realName = ""
			self.roomNumber = ""
			self.dinnerTeam = nil
		}
		else {
			self.about = user.about ?? ""
			self.email = user.email ?? ""
			self.homeLocation = user.homeLocation ?? ""
			self.message = user.message ?? ""
			self.realName = user.realName ?? ""
			self.roomNumber = user.roomNumber ?? ""
			self.dinnerTeam = user.dinnerTeam
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
public struct ReportData: Content {
	/// An optional message from the submitting user.
	var message: String
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
public struct TokenStringData: Content {
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
			throw Abort(
				.internalServerError,
				reason: "Attempt to create TokenStringData for token not assigned to User"
			)
		}
		self.userID = token.$user.id
		self.accessLevel = user.accessLevel
		self.token = token.token
	}

	init?(cacheUser: UserCacheData) {
		guard let tokenString = cacheUser.token else {
			return nil
		}
		self.userID = cacheUser.userID
		self.accessLevel = cacheUser.accessLevel
		self.token = tokenString
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
public struct TwarrtData: Content {
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
	/// If this twarrt is part of a Reply Group, the ID of the group. If replyGroupID == twarrtID, this twarrt is the start of a Reply Group. If nil, there are no replies to this twarrt.
	var replyGroupID: Int?
	/// Whether the current user has bookmarked the twarrt.
	var isBookmarked: Bool
	/// The current user's `LikeType` reaction on the twarrt.
	var userLike: LikeType?
	/// The total number of `LikeType` reactions on the twarrt.
	var likeCount: Int
}

extension TwarrtData {
	init(
		twarrt: Twarrt,
		creator: UserHeader,
		isBookmarked: Bool,
		userLike: LikeType?,
		likeCount: Int,
		overrideQuarantine: Bool = false
	) throws {
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
public struct TwarrtDetailData: Content {
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
	/// The users with "laugh" reactions on the post/twarrt.
	var laughs: [UserHeader]
	/// The users with "like" reactions on the post/twarrt.
	var likes: [UserHeader]
	/// The users with "love" reactions on the post/twarrt.
	var loves: [UserHeader]
}

/// A bool, wrapped in a struct. Used for the results of user capability queries.
///
/// Required by:
/// * `POST /api/v3/karaoke/userIsManager`
///
/// See `UserController.createHandler(_:data:)`, `UserController.addHandler(_:data:)`.
public struct UserAuthorizedToCreateKaraokeLogs: Content {
	/// TRUE if the user is authorized to add entries to the Karaoke Performed Song Log.
	var isAuthorized: Bool
}

/// Used to create a new account or sub-account.
///
/// Required by:
/// * `POST /api/v3/user/create`
/// * `POST /api/v3/user/add`
///
/// See `UserController.createHandler(_:data:)`, `UserController.addHandler(_:data:)`.
public struct UserCreateData: Content {
	/// The user's username.
	var username: String
	/// The user's password.
	var password: String
	/// Verification code, emailed to all cruisegoers by THO before embarkation. On success, user will be created with .verified access level, consuming this code.
	/// Required for creating 'parent' accounts; must be nil when used to create a sub-account with `POST /api/v3/user/add`.
	var verification: String?
}

extension UserCreateData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(password.count >= 6, forKey: .password, or: "password has a 6 character minimum")
		tester.validate(password.count <= 50, forKey: .password, or: "password has a 50 character limit")
		usernameValidations(username: username)
			.forEach {
				tester.addValidationError(forKey: .username, errorString: $0)
			}
		// Registration code can be nil, but if it isn't, it must be a properly formed code.
		if let normalizedCode = verification?.lowercased().replacingOccurrences(of: " ", with: ""),
			normalizedCode.count > 0
		{
			if normalizedCode.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
				|| normalizedCode.count != 6
			{
				tester.addValidationError(
					forKey: .verification,
					errorString: "Malformed registration code. Registration code "
						+ "must be 6 alphanumeric letters; spaces optional"
				)
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
public struct UserHeader: Content {
	/// The user's ID.
	var userID: UUID
	/// The user's username.
	var username: String
	/// The user's displayName.
	var displayName: String?
	/// The user's avatar image.
	var userImage: String?
	/// An optional preferred pronoun or form of address.
	var preferredPronoun: String?
}

extension UserHeader {
	init(user: User) throws {
		self.userID = try user.requireID()
		self.username = user.username
		self.displayName = user.displayName
		self.userImage = user.userImage
		self.preferredPronoun = user.preferredPronoun
	}

	static var Blocked: UserHeader {
		.init(
			userID: Settings.shared.blockedUserID,
			username: "BlockedUser",
			displayName: "BlockedUser",
			userImage: "",
			preferredPronoun: ""
		)
	}
}

/// Returns status about a single Alertword, for either Twarrts of ForumPost hits on that word.
/// Used inside UserNotificationData.
public struct UserNotificationAlertwordData: Content {
	/// Will be one of the user's current alert keywords.
	var alertword: String
	/// The total number of twarrts that include this word since the first time anyone added this alertword. We record alert word hits in
	/// a single global list that unions all users' alert word lists. A search for this alertword may return more hits than this number indicates.
	var twarrtMentionCount: Int
	/// The number of twarrts that include this alertword that the user has not yet seen. Calls to view twarrts with a "?search=" parameter that matches the
	/// alertword will mark all twarrts containing this alertword as viewed.
	var newTwarrtMentionCount: Int
	/// The total number of forum posts that include this word since the first time anyone added this alertword.
	var forumMentionCount: Int
	/// The number of forum posts that include this alertword that the user has not yet seen.
	var newForumMentionCount: Int
}

extension UserNotificationAlertwordData {
	init(_ word: String) {
		alertword = word
		twarrtMentionCount = 0
		newTwarrtMentionCount = 0
		forumMentionCount = 0
		newForumMentionCount = 0
	}
}

/// Provides updates about server global state and the logged in user's notifications.
/// `userNotificationHandler()` is intended to be called frequently by clients (I mean, don't call it once a second).
///
/// Returned by AlertController.userNotificationHandler()
public struct UserNotificationData: Content {
	/// Always an ISO 8601 date in UTC, like "2020-03-07T12:00:00Z"
	var serverTime: String
	/// Server Time Zone offset, in seconds from UTC. One hour before UTC is -3600. EST  timezone is -18000.
	var serverTimeOffset: Int
	/// The geopolitical region identifier that identifies the time zone -- e.g. "America/Los Angeles"
	var serverTimeZoneID: String
	/// Human-readable time zone name, like "EDT"
	var serverTimeZone: String
	/// Features that are turned off by the server. If the `appName` for a feature is `all`, the feature is disabled at the API layer.
	/// For all other appName values, the disable is just a notification that the client should not show the feature to users.
	/// If the list is empty, no features have been disabled.
	var disabledFeatures: [DisabledFeature]
	/// The name of the shipboard Wifi network
	var shipWifiSSID: String?

	/// IDs of all active announcements
	var activeAnnouncementIDs: [Int]

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

	/// The start time of the earliest event that the user has followed with a start time > now. nil if not logged in or no matching event.
	var nextFollowedEventTime: Date?

	/// The event ID of the the next future event the user has followed. This event's start time should always be == nextFollowedEventTime.
	/// If the user has favorited multiple events that start at the same time, this will be random among them.
	var nextFollowedEventID: UUID?

	/// The number of Micro Karaoke songs the user has contributed to and can now view.
	var microKaraokeFinishedSongCount: Int

	/// The start time of the earliest LFG that the user has joined with a start time > now. nil if not logged in or no matching LFG.
	var nextJoinedLFGTime: Date?

	/// The LFG ID of the the next future LFG the user has joined. This LFGs's start time should always be == nextJoinedLFGTime.
	/// If the user has joined multiple LFGs that start at the same time, this will be random among them.
	var nextJoinedLFGID: UUID?

	/// For each alertword the user has, this returns data on hit counts for that word.
	var alertWords: [UserNotificationAlertwordData]

	/// Notification counts that are only relevant for Moderators (and TwitarrTeam).
	public struct ModeratorNotificationData: Content {
		/// The total number of open user reports. Does not count in-process reports (reports being 'handled' by a mod already).
		/// This value counts multiple reports on the same piece of content as separate reports.
		var openReportCount: Int

		/// The number of Seamails to @moderator (more precisely, ones where @moderator is a participant) that have new messages.
		/// This value is very similar to `newSeamailMessageCount`, but for any moderator it gives the number of new seamails for @moderator.
		var newModeratorSeamailMessageCount: Int

		/// The number of Seamails to @TwitarrTeam. Nil if user isn't a member of TwitarrTeam. This is in the Moderator struct because I didn't
		/// want to make *another* sub-struct for TwitarrTeam, just to hold two values.
		var newTTSeamailMessageCount: Int?

		/// Number of forum post @mentions the user has not read for @moderator.
		var newModeratorForumMentionCount: Int

		/// Number of forum post @mentions the user has not read for @twitarrteam. Nil if the user isn't a member of TwitarrTeam.
		/// This is in the Moderator struct because I didn't want to make *another* sub-struct for TwitarrTeam, just to hold two values.
		var newTTForumMentionCount: Int
	}

	/// Will be nil for non-moderator accounts.
	var moderatorData: ModeratorNotificationData?
}

extension UserNotificationData {
	init(
		newFezCount: Int,
		newSeamailCount: Int,
		activeAnnouncementIDs: [Int],
		newAnnouncementCount: Int,
		nextEventTime: Date?,
		nextEvent: UUID?,
		nextLFGTime: Date?,
		nextLFG: UUID?,
		microKaraokeFinishedSongCount: Int
	) {
		serverTime = ISO8601DateFormatter().string(from: Date())
		serverTimeOffset = Settings.shared.timeZoneChanges.tzAtTime().secondsFromGMT(for: Date())
		serverTimeZoneID = Settings.shared.timeZoneChanges.tzAtTime().identifier
		serverTimeZone = Settings.shared.timeZoneChanges.abbrevAtTime()
		self.disabledFeatures = Settings.shared.disabledFeatures.buildDisabledFeatureArray()
		self.shipWifiSSID = Settings.shared.shipWifiSSID
		self.activeAnnouncementIDs = activeAnnouncementIDs
		self.newAnnouncementCount = newAnnouncementCount
		self.twarrtMentionCount = 0
		self.newTwarrtMentionCount = 0
		self.forumMentionCount = 0
		self.newForumMentionCount = 0
		self.newSeamailMessageCount = newSeamailCount
		self.newFezMessageCount = newFezCount
		self.nextFollowedEventTime = nextEventTime
		self.nextFollowedEventID = nextEvent
		self.microKaraokeFinishedSongCount = microKaraokeFinishedSongCount
		self.alertWords = []
		self.nextJoinedLFGID = nextLFG
		self.nextJoinedLFGTime = nextLFGTime
	}

	// Initializes a dummy struct, for when there's no user logged in.
	init() {
		serverTime = ISO8601DateFormatter().string(from: Date())
		serverTimeOffset = Settings.shared.timeZoneChanges.tzAtTime().secondsFromGMT(for: Date())
		serverTimeZoneID = Settings.shared.timeZoneChanges.tzAtTime().identifier
		serverTimeZone = Settings.shared.timeZoneChanges.abbrevAtTime()
		self.disabledFeatures = []
		self.shipWifiSSID = nil
		self.activeAnnouncementIDs = []
		self.newAnnouncementCount = 0
		self.twarrtMentionCount = 0
		self.newTwarrtMentionCount = 0
		self.forumMentionCount = 0
		self.newForumMentionCount = 0
		self.newSeamailMessageCount = 0
		self.newFezMessageCount = 0
		self.nextFollowedEventTime = nil
		self.microKaraokeFinishedSongCount = 0
		self.alertWords = []
		self.nextJoinedLFGTime = nil
	}
}

/// Used to change a user's password. Even when already logged in, users need to provide their current password to set a new password.
///
/// Required by: `POST /api/v3/user/password`
///
/// See `UserController.passwordHandler(_:data:)`.
public struct UserPasswordData: Content {
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
public struct UserProfileUploadData: Content {
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
	/// An optional dinner team assignment.
	var dinnerTeam: DinnerTeam?
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
		self.dinnerTeam = user.dinnerTeam
	}
}

extension UserProfileUploadData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validateStrLenOptional(displayName, min: 2, max: 50, forKey: .displayName, fieldName: "display name")
		tester.validateStrLenOptional(realName, min: 2, max: 50, forKey: .realName, fieldName: "real name")
		tester.validateStrLenOptional(
			preferredPronoun,
			min: 2,
			max: 50,
			forKey: .preferredPronoun,
			fieldName: "pronouns field"
		)
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
public struct UserRecoveryData: Content {
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
		tester.validate(
			recoveryKey.count >= 6,
			forKey: .recoveryKey,
			or: "password/recovery code has a 6 character minimum"
		)
		usernameValidations(username: username)
			.forEach {
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
public struct UserSearch: Content {
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
public struct UserUsernameData: Content {
	/// The user's desired new username.
	var username: String
}

extension UserUsernameData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		usernameValidations(username: username)
			.forEach {
				tester.addValidationError(forKey: .username, errorString: $0)
			}
	}
}

/// Used to verify (register) a created but `.unverified` primary account.
///
/// Required by: `POST /api/v3/user/verify`
///
/// See `UserController.verifyHandler(_:data:)`.
public struct UserVerifyData: Content {
	/// The registration code provided to the user.
	var verification: String
}

extension UserVerifyData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(
			verification.count >= 6 && verification.count <= 7,
			forKey: .verification,
			or: "verification code is 6 letters long (with an optional space in the middle)"
		)
	}
}

// MARK: - Username Validation

/// Three differernt POST structs contain username fields; this fn exists to ensure they all validate the username the same way. This fn is designed to return a list
/// of validation failure strings--if it returns an empty array the username is valid.
private func usernameValidations(username: String) -> [String] {
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
		errorStrings.append(
			"Username separator chars (\(usernameSeparatorString)) can only be in the middle of a username string."
		)
	}
	return errorStrings
}

/// Prometheus Alertmanager webhook alert object.
/// Applied from https://prometheus.io/docs/alerting/latest/configuration/#webhook_config
///
public struct AlertmanagerAlert: Content {
	// Status could be considered a enum since they're well defined. Until we do something fancy with
	// them I'm disinclined to overcomplicate it.
	var status: String
	// List of labels (key: value). Labels can be used for filtering in Prometheus/Alertmanager.
	var labels: [String: String]
	// List of annotations (key: value). Annotations are human metadata in Prometheus/Alertmanager.
	var annotations: [String: String]
	// Date at which the alert was generated.
	var startsAt: Date
	// @TODO This is rendering as something like "0001-01-01T00:00:00Z" which to me implies its a time
	// delta but interpreted as a date. Gah.
	var endsAt: String
	// Identifies the entity that caused the alert.
	var generatorURL: String
	// Fingerprint to identify the alert.
	var fingerprint: String

	// Convenient accessor for the alert name. Annoyingly this is not not passed in as a
	// specific attribute in the webook but rather converted to a label. Just in case the
	// label isn't there we'll still return a string but it will be less helpful.
	func getName() -> String {
		return self.labels["alertname"] ?? "Unknown Alert"
	}

	// Convenient accessor for the alert summary. This is a custom annotation (not label!)
	// applied in the Prometheus rules. It is not part of the webhook spec (being an annotation
	// and all) so it's up to the administrator to configure it correctly.
	// Just in case the annotation isn't there we'll still return a string but it will be less helpful.
	func getSummary() -> String {
		return self.annotations["summary"] ?? "Unknown details."
	}
}

/// Prometheus Alertmanager webhook payload.
/// Applied from https://prometheus.io/docs/alerting/latest/configuration/#webhook_config
///
public struct AlertmanagerWebhookPayload: Content {
	var version: String
	/// Key identifying the group of alerts (e.g. to deduplicate).
	var groupKey: String
	/// How many alerts have been truncated due to "max_alerts".
	var truncatedAlerts: Int
	// Well-known status string of the alert (firing, cleared, etc).
	var status: String
	// Name of the Alertmanager receiver object.
	var receiver: String
	// List of labels (key: value) for the alert group. Labels can be used for filtering in Prometheus/Alertmanager.
	var groupLabels: [String: String]
	// List of labels (key: value) common to all alerts in this group. Labels can be used for filtering in Prometheus/Alertmanager.
	var commonLabels: [String: String]
	// List of annotations (key: value) common to all alerts in this group. Annotations are human metadata in Prometheus/Alertmanager.
	var commonAnnotations: [String: String]
	/// backlink to the Alertmanager.
	var externalURL: String
	// List of AlertmanagerAlert objects that are within this group/update.
	var alerts: [AlertmanagerAlert]
}

/// Healthcheck URL response payload.
/// This smells roughly the same as an error fields-wise without inheriting from the error.
///
public struct HealthResponse: Content {
	/// HTTP status code.
	var status: HTTPResponseStatus = HTTPResponseStatus.ok
	/// Arbitrary response details.
	var reason: String = "OK"
	/// Is this response an error.
	var error: Bool = false
}

// MARK: Personal Events
///
/// Used to return a `PersonalEvent`'s data.
public struct PersonalEventData: Content {
	/// The PersonalEvent's ID. This is the Swiftarr database record for this event.
	var personalEventID: UUID
	/// The personal event's title.
	var title: String
	/// A description of the personal event.
	var description: String?
	/// Starting time of the personal event
	var startTime: Date
	/// Ending time of the personal event. No more than 24 hours after
	/// the startTime since per Chall that makes iCal export get weird.
	var endTime: Date
	/// The timezone that the ship is going to be in when the personal event occurs. Delivered as an abbreviation e.g. "EST".
	var timeZone: String
	/// The timezone ID that the ship is going to be in when the personal event occurs. Example: "America/New_York".
	var timeZoneID: String
	/// The location of the personal event.
	var location: String?
	/// The last time data for this personal event was modified.
	var lastUpdateTime: Date
	/// The owning user of this personal event.
	var owner: UserHeader
	/// Users that the owner has invited to join this personal event.
	/// Should not contain the owner itself (see PersonalEvent.owner above)
	var participants: [UserHeader]
}

extension PersonalEventData {
	init(_ personalEvent: PersonalEvent, ownerHeader: UserHeader, participantHeaders: [UserHeader]) throws {
		let timeZoneChanges = Settings.shared.timeZoneChanges
		self.personalEventID = try personalEvent.requireID()
		self.title = personalEvent.title
		self.description = personalEvent.description
		self.startTime = timeZoneChanges.portTimeToDisplayTime(personalEvent.startTime)
		self.endTime = timeZoneChanges.portTimeToDisplayTime(personalEvent.endTime)
		self.timeZone = timeZoneChanges.abbrevAtTime(self.startTime)
		self.timeZoneID = timeZoneChanges.tzAtTime(self.startTime).identifier
		self.location = personalEvent.location
		self.lastUpdateTime = personalEvent.updatedAt ?? Date()
		self.owner = ownerHeader
		self.participants = participantHeaders
	}
}

/// PersonalEventContentData is used for creating and editing a PersonalEvent.
/// Contains all of the fields that a user can modify.
///
public struct PersonalEventContentData: Content {
	/// The title for the PersonalEvent.
	var title: String
	/// A description of the PersonalEvent.
	var description: String?
	/// The starting time for the PersonalEvent.
	var startTime: Date
	/// The ending time for the PersonalEvent.
	var endTime: Date
	/// The location for the PersonalEvent.
	var location: String?
	/// Users that have been invited to this PersonalEvent.
	/// Should not contain the owner.
	var participants: [UUID]
}

extension PersonalEventContentData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(title.count >= 2, forKey: .title, or: "title field has a 2 character minimum")
		tester.validate(title.count <= 100, forKey: .title, or: "title field has a 100 character limit")
		let timeInterval = endTime.timeIntervalSince(startTime)
		guard timeInterval <= 86400 else {
            throw Abort(.badRequest, reason: "endTime can be no more than 24 hours after startTime")
        }
	}
}
