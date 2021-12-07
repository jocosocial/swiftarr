import Vapor

/// Used to return `FriendlyFezEdit` data for moderators. The only primary data an edit stores is the title, info, and location text fields.
///
///	Included in:
///	* `FezModerationData`
///	
/// Returned by:
/// * `GET /api/v3/mod/fez/ID`
public struct FezEditLogData: Content {
	/// The ID of the fez.
    var fezID: UUID
	/// The ID of the edit.
    var editID: UUID
    /// The timestamp of the edit.
    var createdAt: Date
    /// Who initiated the edit. Usually the fez creator, but could be a moderator. Note that the saved edit shows the state BEFORE the edit,
    /// therefore the 'author' here changed the contents to those of the NEXT edit (or to the current state).
    var author: UserHeader
    /// The title of the fez just before `author` edited it.
    var title: String
    /// The info field just before `author` edited it.
    var info: String
    /// The location field just before `author` edited it.
    var location: String
}

extension FezEditLogData {
	init(_ edit: FriendlyFezEdit, on req: Request) throws {
		fezID = edit.$fez.id
		editID = try edit.requireID()
		createdAt = edit.createdAt ?? Date()
		author = try req.userCache.getHeader(edit.$editor.id)
		title = edit.title
		info = edit.info
		location = edit.location
	}
}

/// Used to return data a moderator needs to moderate a fez. 
///	
/// Returned by:
/// * `GET /api/v3/mod/fez/:fez_id`
/// 
/// Note that FezPosts can't be edited and don't have an edit log.
///
/// See `ModerationController.fezModerationHandler(_:)`
public struct FezModerationData: Content {
	var fez: FezData
	var isDeleted: Bool
	var moderationStatus: ContentModerationStatus
	var edits: [FezEditLogData]
	var reports: [ReportModerationData]
}

/// Used to return data a moderator needs to moderate a fez post.
///	
/// Returned by:
/// * `GET /api/v3/mod/fezpost/:post_id`
///
/// See `ModerationController.fezPostModerationHandler(_:)`
public struct FezPostModerationData: Content {
	var fezPost: FezPostData
	var fezID: UUID
	var isDeleted: Bool
	var moderationStatus: ContentModerationStatus
	var reports: [ReportModerationData]
}

/// Used to return `ForumEdit` data for moderators. The only primary data a ForumEdit stores is the title the forum had before the edit.
///
///	Included in:
///	* `ForumPostModerationData`
///	* `TwarrtModerationData`
///	
/// Returned by:
/// * `GET /api/v3/mod/forum/id`
public struct ForumEditLogData: Content {
	/// The ID of the forum.
    var forumID: UUID
	/// The ID of the edit.
    var editID: UUID
    /// The timestamp of the edit.
    var createdAt: Date
    /// Who initiated the edit. Usually the forum author, but could be a moderator. Note that the saved edit shows the state BEFORE the edit,
    /// therefore the 'author' here changed the contents to those of the NEXT edit (or to the current state).
    var author: UserHeader
    /// The title of the forum just BEFORE `author` edited it.
    var title: String
}

extension ForumEditLogData {
	init(_ edit: ForumEdit, on req: Request) throws {
		forumID = edit.$forum.id
		editID = try edit.requireID()
		createdAt = edit.createdAt ?? Date()
		author = try req.userCache.getHeader(edit.$editor.id)
		title = edit.title
	}
}

/// Used to return data a moderator needs to moderate a forum. 
///	
/// Returned by:
/// * `GET /api/v3/mod/forum/id`
///
/// See `ModerationController.forumModerationHandler(_:)`
public struct ForumModerationData: Content {
    /// The forum's ID.
    var forumID: UUID
    /// the forum's category.
	var categoryID: UUID
    /// The forum's creator.
	var creator: UserHeader
    /// The forum's title.
    var title: String
    /// Time forum was created.
    var createdAt: Date
    /// Whether the forum is in read-only state, or is quarantined.
    var moderationStatus: ContentModerationStatus
    /// TRUE if the forum has been soft-deleted
	var isDeleted: Bool
	/// Previous edits to the forum title
	var edits: [ForumEditLogData]
	/// User reports against this forum
	var reports: [ReportModerationData]
}

extension ForumModerationData {
	init(_ forum: Forum, edits: [ForumEditLogData], reports: [ReportModerationData], on req: Request) throws {
		forumID = try forum.requireID()
		categoryID = forum.$category.id
		creator = try req.userCache.getHeader(forum.$creator.id)
		title = forum.title
		createdAt = forum.createdAt ?? Date()
		moderationStatus = forum.moderationStatus
		isDeleted = false
		if let deleteTime = forum.deletedAt, deleteTime < Date() {
			isDeleted = true
		}
		self.edits = edits
		self.reports = reports
	}
}

/// Used to return data a moderator needs to moderate a twarrt. 
///	
/// Returned by:
/// * `GET /api/v3/mod/forumPost/id`
///
/// See `ModerationController.forumPostModerationHandler(_:)`
public struct ForumPostModerationData: Content {
	/// The post in question
	var forumPost: PostDetailData
	/// TRUE if the post has been soft-deleted (A soft-deleted post appears deleted, doesn't appear in its forum or in searches,
	// but can still be viewed by moderators when accessed via a report or a moderationAction).
	var isDeleted: Bool
	/// The moderation status of this post. Whether the post has been locked or quarantined.
	var moderationStatus: ContentModerationStatus
	/// Previous edits to the post, along with the editors and timestamps.
	var edits: [PostEditLogData]
	/// User reports against this post.
	var reports: [ReportModerationData]
}

/// Returns data about an instance of a moderator using their mod powers to edit/delete a user's content, edit a user's profile fields, or change a user's privledges.
public struct ModeratorActionLogData: Content {
	/// The ID of this log entry
	var id: UUID
	/// What action the moderator took.
	var actionType: ModeratorActionType
	/// The type of content that got moderated: Twarrt, forum, forum post, fez, fez post, or user profile.
	var contentType: ReportType
	/// The ID of the content. Could be an Int or a UUID, dpeeneding on `contentType`
	var contentID: String
	/// When the moderation actdion happened.
	var timestamp: Date
	/// The user that did the action
	var moderator: UserHeader
	/// The original author of the content that was moderated.
	var targetUser: UserHeader
}

extension ModeratorActionLogData {
	init(action: ModeratorAction, on req: Request) throws {
		id = try action.requireID()
		actionType = action.actionType
		contentType = action.contentType
		contentID = action.contentID
		timestamp = action.createdAt ?? Date()
		moderator = try req.userCache.getHeader(action.$actor.id)
		targetUser = try req.userCache.getHeader(action.$target.id)
	}
}

/// Used to return a `TwarrtEdit` or `ForumPost`'s data for moderators. The two models use the same data structure, as all the fields happen to be the same.
///
///	Included in:
///	* `ForumPostModerationData`
///	* `TwarrtModerationData`
///	
/// Returned by:
/// * `GET /api/v3/mod/twarrt/id`
public struct PostEditLogData: Content {
	/// The ID of the post. Depending on context, could be a twarrtID or a forumPostID.
    var postID: Int
	/// The ID of the edit.
    var editID: UUID
    /// The timestamp of the post.
    var createdAt: Date
    /// Who initiated the edit. Usually the post author, but could be a moderator. Note that the saved edit shows the state BEFORE the edit,
    /// therefore the 'author' here changed the contents to those of the NEXT edit (or to the current state).
    var author: UserHeader
    /// The text of the forum post.
    var text: String
    /// The filenames of the twarrt's optional images.
    var images: [String]?
}

extension PostEditLogData {
    init(edit: TwarrtEdit, editor: UserHeader) throws {
    	postID = edit.$twarrt.id
    	editID = try edit.requireID()
    	createdAt = edit.createdAt ?? Date()
    	author = editor
    	text = edit.text
    	images = edit.images    	
    }
    
    init(edit: ForumPostEdit, editor: UserHeader) throws {
    	postID = edit.$post.id
    	editID = try edit.requireID()
    	createdAt = edit.createdAt ?? Date()
    	author = editor
    	text = edit.postText
    	images = edit.images    	
    }
}

/// Used to return data moderators need to view previous edits a user made to their profile. 
/// This structure will have either the `profileData` or `profileImage` field populated.
/// An array of these stucts is placed inside `ProfileModerationData`.
public struct ProfileEditLogData: Content {
	var editID: UUID
	var createdAt: Date
	var author: UserHeader
	var profileData: UserProfileUploadData?
	var profileImage: String?
}

extension ProfileEditLogData {
	init(_ edit: ProfileEdit, on req: Request) throws {
		editID = try edit.requireID()
		createdAt = edit.createdAt ?? Date()
		author = try req.userCache.getHeader(edit.$editor.id)
		profileData = edit.profileData
		profileImage = edit.profileImage
	}
}

/// Used to return data moderators need to evaluate a user's profile. Shows the user's current profile values, past edits, reports made against
/// the profile, and the user's profile moderationStatus.
public struct ProfileModerationData: Content {
	var profile: UserProfileUploadData
	var moderationStatus: ContentModerationStatus
	var edits: [ProfileEditLogData]
	var reports: [ReportModerationData]
}

/// Used to return data about `Report`s submitted by users. Only Moderators and above have access.
///
/// Required by:
/// * `GET /api/v3/mod/reports`
public struct ReportModerationData: Content {
	/// The id of the report.
	var id: UUID
	/// The type of content being reported
	var type: ReportType
	/// The ID of the reported entity. Could resolve to an Int or a UUID, depending on the value of`type`.
	var reportedID: String
	/// The user that authored the content being reported..
	var reportedUser: UserHeader
	/// Text the report author wrote when submitting the report.
	var submitterMessage: String?
	/// The user that submitted the report--NOT the user whose content is being reported.
	var author: UserHeader
	/// The mod who handled (or closed) the report. 
	var handledBy: UserHeader?
	/// TRUE if the report has been closed by moderators.
	var isClosed: Bool
	/// The time the submitter filed the report.
	var creationTime: Date
	/// The last time the report has been modified.
	var updateTime: Date
}

extension ReportModerationData {
	init(req: Request, report: Report) throws {
		id = try report.requireID()
		type = report.reportType
		reportedID = report.reportedID
		reportedUser = try req.userCache.getHeader(report.$reportedUser.id)
		submitterMessage = report.submitterMessage
		isClosed = report.isClosed
		creationTime = report.createdAt ?? Date()
		updateTime = report.updatedAt ?? Date()
		author = try req.userCache.getHeader(report.$submitter.id)
		if let modID = report.$handledBy.id {
			handledBy = try req.userCache.getHeader(modID)
		}
	}
}

/// Used to return data a moderator needs to moderate a twarrt. 
///	
/// Returned by:
/// * `GET /api/v3/mod/twarrt/id`
///
/// See `ModerationController.twarrtModerationHandler(_:)`
public struct TwarrtModerationData: Content {
	var twarrt: TwarrtData
	var isDeleted: Bool
	var moderationStatus: ContentModerationStatus
	var edits: [PostEditLogData]
	var reports: [ReportModerationData]
}

/// Used to return data a moderator needs to moderate a user. 
///	
/// Returned by:
/// * `GET /api/v3/mod/user/id`
///
/// See `ModerationController.userModerationHandler(_:)`
public struct UserModerationData: Content {
	/// 'Main' account for this user
	var header: UserHeader
	/// Sub-accounts that this user has created.			
	var subAccounts: [UserHeader]
	/// This user's access level. Main user and all sub accounts share an access level.
	var accessLevel: UserAccessLevel
	/// If this user is temporarily quarantined, this will contain the end time for the quarantine. While quarantined, the user can log in and read content as normal
	/// but cannot create content in any public area (posts, edit posts, create forums, participate in FriendlyFezzes, or edit their profile). 
	var tempQuarantineEndTime: Date?
	/// All reports against any user account this user controls.
	var reports: [ReportModerationData]
}

extension UserModerationData {
	init(user: User, subAccounts: [User], reports: [ReportModerationData]) throws {
		header = try UserHeader(user: user)
		accessLevel = user.accessLevel
		tempQuarantineEndTime =  nil
		if let endTime = user.tempQuarantineUntil, endTime > Date() {
			tempQuarantineEndTime = user.tempQuarantineUntil
		}
		self.subAccounts = try subAccounts.map { try UserHeader(user: $0) }
		self.reports = reports
	}
}
