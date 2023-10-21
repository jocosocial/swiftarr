import Crypto
import FluentSQL
import Vapor

/// 	The collection of `/api/v3/mod/` route endpoints and handler functions related to moderation tasks.
///
/// 	All routes in this group should be restricted to users with moderation priviliges. This controller returns data of
/// 	a privileged nature, including contents of user reports, edit histories of user content, and log data about moderation actions.
///
/// 	Note that some moderation actions aren't in this file. Most such endpoints have a handler method allowing a user
/// 	to operate on their own content, but also allowing a mod to operate on other users' content. For example, `twarrtUpdateHandler` lets
/// 	a user edit a twarrt they wrote, but also lets mods edit any user's twarrt.
///
/// 	The routes in this controller that return data on various Reportable content types are designed to return everything a Mod might need
/// 	to make moderation decisions, all in one call. In many cases that means calls return multiple array types with no paging or array limits.
/// 	In non-degenerate cases the arrays should less than ~20 elements. Additionally, there are few moderators and they won't be calling these
/// 	methods multiple times per second.
struct ModerationController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/mod endpoints
		let modRoutes = app.grouped("api", "v3", "mod")

		// instantiate authentication middleware
		let requireModMiddleware = RequireModeratorMiddleware()

		// endpoints available for Moderators only
		let moderatorAuthGroup = addTokenCacheAuthGroup(to: modRoutes).grouped([requireModMiddleware])
		moderatorAuthGroup.get("reports", use: reportsHandler)
		moderatorAuthGroup.post("reports", ":report_id", "handleall", use: beginProcessingReportsHandler)
		moderatorAuthGroup.post("reports", ":report_id", "closeall", use: closeReportsHandler)
		moderatorAuthGroup.get("moderationlog", use: moderatorActionLogHandler)

		moderatorAuthGroup.get("twarrt", twarrtIDParam, use: twarrtModerationHandler)
		moderatorAuthGroup.post(
			"twarrt",
			twarrtIDParam,
			"setstate",
			modStateParam,
			use: twarrtSetModerationStateHandler
		)

		moderatorAuthGroup.get("forumpost", postIDParam, use: forumPostModerationHandler)
		moderatorAuthGroup.post(
			"forumpost",
			postIDParam,
			"setstate",
			modStateParam,
			use: forumPostSetModerationStateHandler
		)

		moderatorAuthGroup.get("forum", forumIDParam, use: forumModerationHandler)
		moderatorAuthGroup.post("forum", forumIDParam, "setstate", modStateParam, use: forumSetModerationStateHandler)
		moderatorAuthGroup.post("forum", forumIDParam, "setcategory", categoryIDParam, use: forumSetCategoryHandler)

		moderatorAuthGroup.get("chatgroup", chatGroupIDParam, use: chatGroupModerationHandler)
		moderatorAuthGroup.post("chatgroup", chatGroupIDParam, "setstate", modStateParam, use: chatGroupSetModerationStateHandler)

		moderatorAuthGroup.get("chatgrouppost", chatGroupPostIDParam, use: chatGroupPostModerationHandler)
		moderatorAuthGroup.post(
			"chatgrouppost",
			chatGroupPostIDParam,
			"setstate",
			modStateParam,
			use: ChatGroupPostsetModerationStateHandler
		)

		moderatorAuthGroup.get("profile", userIDParam, use: profileModerationHandler)
		moderatorAuthGroup.post(
			"profile",
			userIDParam,
			"setstate",
			modStateParam,
			use: profileSetModerationStateHandler
		)

		moderatorAuthGroup.get("user", userIDParam, use: userModerationHandler)
		moderatorAuthGroup.post("user", userIDParam, "setaccesslevel", accessLevelParam, use: userSetAccessLevelHandler)
		moderatorAuthGroup.post(
			"user",
			userIDParam,
			"tempquarantine",
			":quarantine_length",
			use: applyUserTempQuarantine
		)
	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

	/// `GET /api/v3/mod/reports`
	///
	/// Retrieves the full `Report` model of all reports.
	///
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: An array of `Report` objects
	func reportsHandler(_ req: Request) async throws -> [ReportModerationData] {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		let reports = try await Report.query(on: req.db).sort(\.$createdAt, .descending).all()
		return try reports.map { try ReportModerationData.init(req: req, report: $0) }
	}

	/// `POST /api/v3/mod/reports/ID/handleall`
	///
	/// This call is how a Moderator can take a user Report off the queue and begin handling it. More correctly, it takes all user reports referring to the same
	/// piece of content and marks them all handled at once.
	///
	/// Moving reports through the 'handling' state is not necessary--you can go straight to 'closed'--but this marks the reports as being 'taken' by the given mod
	/// so other mods can avoid duplicate or conflicting work. Also, any ModeratorActions taken while a mod has reports in the 'handling' state get tagged with an
	/// identifier that matches the actions to the reports. Reports should be closed once a mod is done with them.
	/// - Parameter reportID: in URL path. Note that this method actually operates on all reports referring to the same content as the indicated report.
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: 200 OK on success
	func beginProcessingReportsHandler(_ req: Request) async throws -> HTTPStatus {
		// TODO: This could benefit from checks that the mod doesn't currently have an actionGroup (that is, already handling a report)
		// and that the reports aren't already being handled by another mod. But, need to think about process--don't want reports getting stuck.
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		let report = try await Report.findFromParameter("report_id", on: req)
		let groupID = UUID()
		try await Report.query(on: req.db)
			.filter(\.$reportType == report.reportType)
			.filter(\.$reportedID == report.reportedID)
			.filter(\.$isClosed == false)
			.set(\.$handledBy.$id, to: cacheUser.userID)
			.set(\.$actionGroup, to: groupID)
			.update()
		if let user = try await User.find(cacheUser.userID, on: req.db) {
			user.actionGroup = groupID
			try await user.save(on: req.db)
		}
		return .ok
	}

	/// `POST /api/v3/mod/reports/ID/closeall`
	///
	/// Closes all reports filed against the same piece of content as the given report. That is, if there are several user reports
	/// concerning the same post, this will close all of them.
	///
	/// - Parameter reportID: in URL path. Note that this method actually operates on all reports referring to the same content as the indicated report.
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: 200 OK on success
	func closeReportsHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		let report = try await Report.findFromParameter("report_id", on: req)
		try await Report.query(on: req.db)
			.filter(\.$reportType == report.reportType)
			.filter(\.$reportedID == report.reportedID)
			.filter(\.$isClosed == false)
			.set(\.$isClosed, to: true)
			.update()
		if let user = try await User.find(cacheUser.userID, on: req.db) {
			user.actionGroup = nil
			try await user.save(on: req.db)
		}
		return .ok
	}

	/// `GET /api/v3/mod/moderationlog`
	///
	/// Retrieves ModeratorAction records. These records are a log of Mods using their Mod powers. Generally, if an action 1) modifies the database and
	/// 2) requires that the acting user be a mod to perform the action, it will get logged.
	///
	/// - Note: A mod editing/deleting their own content will not get logged, even if they use a Moderator-only API call to do it.
	///
	/// **URL Query Parameters:**
	/// * `?start=INT` - the offset from the anchor to start. Offset only counts twarrts that pass the filters.
	/// * `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50
	///
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: An array of `ModeratorActionLogData` records.
	func moderatorActionLogHandler(_ req: Request) async throws -> [ModeratorActionLogData] {
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
		let result = try await ModeratorAction.query(on: req.db).range(start..<(start + limit))
			.sort(\.$createdAt, .descending)
			.all().map { try ModeratorActionLogData(action: $0, on: req) }
		return result
	}

	/// `GET /api/v3/mod/twarrt/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a twarrt. Works if twarrt has been deleted. Shows
	/// twarrt's quarantine and reviewed states.
	///
	/// The `TwarrtModerationData` contains:
	/// * The current twarrt contents, even if its deleted
	/// * Previous edits of the twarrt
	/// * Reports against the twarrt
	/// * The twarrt's current deletion and moderation status.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `TwarrtModerationData` containing a bunch of data pertinient to moderating the twarrt.
	func twarrtModerationHandler(_ req: Request) async throws -> TwarrtModerationData {
		guard let paramVal = req.parameters.get(twarrtIDParam.paramString), let twarrtID = Int(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(twarrtIDParam.paramString) is missing.")
		}
		guard let twarrt = try await Twarrt.query(on: req.db).filter(\._$id == twarrtID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")
		}
		let reports = try await Report.query(on: req.db).filter(\.$reportType == .twarrt)
			.filter(\.$reportedID == paramVal)
			.sort(\.$createdAt, .descending).all()
		let edits = try await twarrt.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
		let twarrtData = try TwarrtData(
			twarrt: twarrt,
			creator: authorHeader,
			isBookmarked: false,
			userLike: nil,
			likeCount: 0,
			overrideQuarantine: true
		)
		let editData: [PostEditLogData] = try edits.map {
			let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
			return try PostEditLogData(edit: $0, editor: editAuthorHeader)
		}
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = TwarrtModerationData(
			twarrt: twarrtData,
			isDeleted: twarrt.deletedAt != nil,
			moderationStatus: twarrt.moderationStatus,
			edits: editData,
			reports: reportData
		)
		return modData
	}

	/// `POST /api/v3/mod/twarrt/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the twarrt identified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the user owns the twarrt.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func twarrtSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		try twarrt.moderationStatus.setFromParameterString(modState)
		await twarrt.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(twarrt.moderationStatus),
			user: user,
			on: req
		)
		try await twarrt.save(on: req.db)
		return .ok
	}

	/// `GET /api/v3/mod/forumpost/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a forumPost. Works if forumPost has been deleted. Shows
	/// forumPost's quarantine and reviewed states.
	///
	/// The `ForumPostModerationData` contains:
	/// * The current post contents, even if its deleted
	/// * Previous edits of the post
	/// * Reports against the post
	/// * The post's current deletion and moderation status.
	///
	/// - Parameter postID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ForumPostModerationData` containing a bunch of data pertinient to moderating the post.
	func forumPostModerationHandler(_ req: Request) async throws -> ForumPostModerationData {
		guard let paramVal = req.parameters.get(postIDParam.paramString), let postID = Int(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(postIDParam.paramString) is missing.")
		}
		guard let post = try await ForumPost.query(on: req.db).filter(\._$id == postID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .forumPost)
			.filter(\.$reportedID == paramVal)
			.sort(\.$createdAt, .descending).all()
		let edits = try await post.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let authorHeader = try req.userCache.getHeader(post.$author.id)
		let postData = try PostDetailData(post: post, author: authorHeader, overrideQuarantine: true)
		let editData: [PostEditLogData] = try edits.map {
			let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
			return try PostEditLogData(edit: $0, editor: editAuthorHeader)
		}
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = ForumPostModerationData(
			forumPost: postData,
			isDeleted: post.deletedAt != nil,
			moderationStatus: post.moderationStatus,
			edits: editData,
			reports: reportData
		)
		return modData
	}

	/// `POST /api/v3/mod/forumpost/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the post idententified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the user owns the post.
	///
	/// - Parameter postID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func forumPostSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let forumPost = try await ForumPost.findFromParameter(postIDParam, on: req)
		try forumPost.moderationStatus.setFromParameterString(modState)
		await forumPost.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(forumPost.moderationStatus),
			user: user,
			on: req
		)
		try await forumPost.save(on: req.db)
		return .ok
	}

	/// `GET /api/v3/mod/forum/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a forum. Works if forum has been deleted. Shows
	/// forum's quarantine and reviewed states. Reports against forums should be reserved for reporting problems with the forum's title.
	/// Likely, they'll also get used to report problems with individual posts.
	///
	/// The `ForumModerationData` contains:
	/// * The current forum contents, even if its deleted
	/// * Previous edits of the forum
	/// * Reports against the forum
	/// * The forum's current deletion and moderation status.
	///
	/// - Parameter forumID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ForumModerationData`  containing a bunch of data pertinient to moderating the forum.
	func forumModerationHandler(_ req: Request) async throws -> ForumModerationData {
		guard let forumIDString = req.parameters.get(forumIDParam.paramString), let forumID = UUID(forumIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(forumIDParam.paramString) is missing.")
		}
		guard let forum = try await Forum.query(on: req.db).filter(\.$id == forumID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no value found for identifier '\(forumID)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .forum)
			.filter(\.$reportedID == forumIDString)
			.sort(\.$createdAt, .descending).all()
		let edits = try await forum.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let editData: [ForumEditLogData] = try edits.map {
			return try ForumEditLogData($0, on: req)
		}
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = try ForumModerationData(forum, edits: editData, reports: reportData, on: req)
		return modData
	}

	/// `POST /api/v3/mod/forum/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the forum idententified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the current user owns the forum.
	///
	/// - Parameter forumID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func forumSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let forum = try await Forum.findFromParameter(forumIDParam, on: req)
		try forum.moderationStatus.setFromParameterString(modState)
		await forum.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(forum.moderationStatus),
			user: user,
			on: req
		)
		try await forum.save(on: req.db)
		return .ok
	}

	/// `POST /api/v3/mod/forum/:forum_ID/setcategory/:category_ID
	///
	/// Moderator only. Moves the indicated forum into the indicated category. Logs the action to the moderation log.
	func forumSetCategoryHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		let newCategory = try await Category.findFromParameter(categoryIDParam, on: req)
		let forum = try await Forum.findFromParameter(forumIDParam, on: req, builder: { $0.with(\.$category) })
		let oldCategory = forum.category
		guard try oldCategory.requireID() != newCategory.requireID() else {
			throw Abort(.badRequest, reason: "Cannot move forum--forum is already in the requested category.")
		}
		oldCategory.forumCount -= 1
		newCategory.forumCount += 1
		// Set forum's new parent, also update the forum's accessLevelToView.
		try await ForumEdit(forum: forum, editorID: user.userID, categoryChanged: true).save(on: req.db)
		forum.$category.id = try newCategory.requireID()
		forum.$category.value = newCategory
		try await req.db.transaction { db in
			try await forum.save(on: db)
			try await oldCategory.save(on: db)
			try await newCategory.save(on: db)
			await forum.logIfModeratorAction(.move, user: user, on: req)
		}
		return .ok
	}

	/// `GET /api/v3/mod/chatgroup/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a ChatGroup. Works if chatgroup has been deleted. Shows
	/// chatgroup's quarantine and reviewed states.
	///
	/// The `ChatGroupModerationData` contains:
	/// * The current chatgroup contents, even if its deleted
	/// * Previous edits of the chatgroup
	/// * Reports against the chatgroup
	/// * The chatgroup's current deletion and moderation status.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupModerationData` containing a bunch of data pertinient to moderating the forum.
	func chatGroupModerationHandler(_ req: Request) async throws -> ChatGroupModerationData {
		guard let lfgIDString = req.parameters.get(chatGroupIDParam.paramString), let lfgID = UUID(lfgIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(chatGroupIDParam.paramString) is missing.")
		}
		guard let lfg = try await FriendlyChatGroup.query(on: req.db).filter(\.$id == lfgID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no LFG found for identifier '\(lfgID)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .chatgroup)
			.filter(\.$reportedID == lfgIDString)
			.sort(\.$createdAt, .descending).all()
		let edits = try await lfg.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let ownerHeader = try req.userCache.getHeader(lfg.$owner.id)
		let chatGroupData = try ChatGroupData(chatgroup: lfg, owner: ownerHeader)
		let editData: [ChatGroupEditLogData] = try edits.map {
			return try ChatGroupEditLogData($0, on: req)
		}
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = ChatGroupModerationData(
			chatgroup: chatGroupData,
			isDeleted: lfg.deletedAt != nil,
			moderationStatus: lfg.moderationStatus,
			edits: editData,
			reports: reportData
		)
		return modData
	}

	/// ` POST /api/v3/mod/chatgroup/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the chatgroup identified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the current user owns the chatgroup.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func chatGroupSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let lfg = try await FriendlyChatGroup.findFromParameter(chatGroupIDParam, on: req)
		try lfg.moderationStatus.setFromParameterString(modState)
		await lfg.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(lfg.moderationStatus),
			user: user,
			on: req
		)
		try await lfg.save(on: req.db)
		return .ok
	}

	/// `GET /api/v3/mod/chatgrouppost/:post_id`
	///
	/// Moderator only. Returns info admins and moderators need to review a ChatGroup post. Works if post has been deleted. Shows
	/// chatgroup's quarantine and reviewed states.  Unlike most other content types, ChatGroup Posts cannot be edited (although they may be deleted).
	///
	/// The `ChatGroupPostModerationData` contains:
	/// * The current post contents, even if its deleted
	/// * Reports against the post
	/// * The post's current deletion and moderation status.
	///
	/// - Parameter chatGroupPostID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupPostModerationData` containing a bunch of data pertinient to moderating the forum.
	func chatGroupPostModerationHandler(_ req: Request) async throws -> ChatGroupPostModerationData {
		guard let postIDString = req.parameters.get(chatGroupPostIDParam.paramString), let postID = Int(postIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(chatGroupPostIDParam.paramString) is missing.")
		}
		guard let lfgPost = try await ChatGroupPost.query(on: req.db).filter(\.$id == postID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no LFG Post found for identifier '\(postID)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .chatGroupPost)
			.filter(\.$reportedID == postIDString)
			.sort(\.$createdAt, .descending).all()
		let authorHeader = try req.userCache.getHeader(lfgPost.$author.id)
		let chatGroupPostData = try ChatGroupPostData(post: lfgPost, author: authorHeader, overrideQuarantine: true)
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = ChatGroupPostModerationData(
			chatGroupPost: chatGroupPostData,
			chatGroupID: lfgPost.$chatGroup.id,
			isDeleted: lfgPost.deletedAt != nil,
			moderationStatus: lfgPost.moderationStatus,
			reports: reportData
		)
		return modData
	}

	/// ` POST /api/v3/mod/chatgrouppost/:post_id/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the chatgroup post identified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the current user authored the post.
	///
	/// - Parameter chatGroupPostID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func ChatGroupPostsetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let lfgPost = try await ChatGroupPost.findFromParameter(chatGroupPostIDParam, on: req)
		try lfgPost.moderationStatus.setFromParameterString(modState)
		await lfgPost.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(lfgPost.moderationStatus),
			user: user,
			on: req
		)
		try await lfgPost.save(on: req.db)
		return .ok
	}

	/// ` GET /api/v3/mod/profile/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a User Profile. The returned info pertains to the user's profile and avatar image --
	/// for example, the web site puts the button allowing mods to edit a user's profile fields on this page.
	///
	/// The `ProfileModerationData` contains:
	/// * The user's profile info and avatar
	/// * Previous edits of the profile and avatar
	/// * Reports against the user's profile
	/// * The user's current  moderation status.
	///
	/// - Parameter userID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ProfileModerationData` containing a bunch of data pertinient to moderating the user's profile.
	func profileModerationHandler(_ req: Request) async throws -> ProfileModerationData {
		guard let targetUserIDString = req.parameters.get(userIDParam.paramString),
			let targetUserID = UUID(targetUserIDString)
		else {
			throw Abort(.badRequest, reason: "Request parameter \(userIDParam.paramString) is missing or isn't a UUID.")
		}
		guard let targetUser = try await User.query(on: req.db).filter(\.$id == targetUserID).withDeleted().first()
		else {
			throw Abort(.notFound, reason: "no User found for identifier '\(targetUserID)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .userProfile)
			.filter(\.$reportedID == targetUserIDString)
			.sort(\.$createdAt, .descending).all()
		let edits = try await targetUser.$edits.query(on: req.db).sort(\.$createdAt, .descending).all()
		let userProfileData = try UserProfileUploadData(user: targetUser)
		let editData: [ProfileEditLogData] = try edits.map {
			return try ProfileEditLogData($0, on: req)
		}
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = ProfileModerationData(
			profile: userProfileData,
			moderationStatus: targetUser.moderationStatus,
			edits: editData,
			reports: reportData
		)
		return modData
	}

	/// ` POST /api/v3/mod/profile/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the profile idententified by userID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the moderator is changing state on their own profile..
	///
	/// - Parameter userID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func profileSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		try targetUser.moderationStatus.setFromParameterString(modState)
		await targetUser.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(targetUser.moderationStatus),
			user: user,
			on: req
		)
		try await targetUser.save(on: req.db)
		return .ok
	}

	/// ` GET /api/v3/mod/user/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a User. User moderation in this context means actions taken against the User account
	/// itself,  such as banning and temp-quarantining. These actions don't edit or remove content but prevent the user from creating any more content.
	///
	/// The `UserModerationData` contains:
	/// * UserHeaders for the User's primary account and any sub-accounts.
	/// * Reports against content authored by any of the above accounts, for all content types (twarrt, forum posts, profile, user image)
	/// * The user's current access level.
	/// * Any temp ban the user has.
	///
	/// - Parameter userID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `UserModerationData` containing a bunch of data pertinient to moderating the forum.
	func userModerationHandler(_ req: Request) async throws -> UserModerationData {
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		let allAccounts = try await targetUser.allAccounts(on: req.db)
		let allUserIDs = try allAccounts.map { try $0.requireID() }
		let reports = try await Report.query(on: req.db).filter(\.$reportedUser.$id ~~ allUserIDs)
			.sort(\.$createdAt, .descending).all()
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = try UserModerationData(
			user: allAccounts[0],
			subAccounts: Array(allAccounts.dropFirst()),
			reports: reportData
		)
		return modData
	}

	/// ` POST /api/v3/mod/user/ID/setaccesslevel/STRING`
	///
	/// Moderator only. Sets the accessLevel enum on the user idententified by userID to the `UserAccessLevel` in STRING.
	/// Moderators (and above) cannot use this method to change the access level of other mods (and above). Nor can they use this to
	/// reduce their own access level to non-moderator status.
	///
	/// This method cannot be used to elevate access level to `moderator` or higher. APIs to do this are in AdminController.
	///
	/// The primary account and all sub-accounts linked to the given User account are affected by the change in access level. The passed-in UserID may
	/// be either a primary or sub-account.
	///
	/// - Parameter userID: in URL path.
	/// - Parameter accessLevel: in URL path. Value must match a `UserAccessLevel` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested access level was set.
	func userSetAccessLevelHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.canModerateUsers() else {
			throw Abort(.badRequest, reason: "This user cannot set access levels.")
		}
		guard let accessLevelString = req.parameters.get(accessLevelParam.paramString),
			let targetAccessLevel = UserAccessLevel.fromRawString(accessLevelString),
			[.unverified, .banned, .quarantined, .verified].contains(targetAccessLevel)
		else {
			throw Abort(
				.badRequest,
				reason: "Invalid target accessLevel. Must be one of unverified, banned, quarantined, verified."
			)
		}
		guard ![.banned, .unverified].contains(targetAccessLevel) || user.accessLevel.hasAccess(.tho) else {
			throw Abort(.badRequest, reason: "THO access level required to set access level to Banned or Unverified.")
		}
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		guard targetUser.accessLevel != .banned || user.accessLevel.hasAccess(.tho) else {
			throw Abort(.badRequest, reason: "THO access level required to change access level from Banned.")
		}
		let allAccounts = try await targetUser.allAccounts(on: req.db)
		// Disallow changing access level for 'special' accounts -- THO, admin, TwitarrTeam and such.
		try allAccounts.forEach { account in
			try guardNotSpecialAccount(account)
		}
		// If the user has any accounts with Moderator or higher access, we can't bulk-modify, unless
		// we're marking accounts Verified. Lowering the access level of a Mod should require approval
		// of someone who can promote/demote mods. And, banning all of a mod's accounts except the one
		// with Mod privileges doesn't work--they can just log onto the mod acct and un-ban themselves.
		if targetAccessLevel != .verified {
			try allAccounts.forEach { account in
				if account.accessLevel >= UserAccessLevel.moderator {
					throw Abort(
						.badRequest,
						reason: """
														Target user has \(allAccounts.count) accounts and their account \"\(account.username)\" \
														has elevated access (Moderator or higher). You need to demote their access first.
														"""
					)
				}
			}
		}
		// Log the action against the parent account.
		if let modSettableAccessLevel = ModeratorActionType.setFromAccessLevel(targetAccessLevel) {
			await allAccounts[0].logIfModeratorAction(modSettableAccessLevel, user: user, on: req)
		}
		for targetUserAccount in allAccounts {
			if targetUserAccount.accessLevel <= .verified {
				targetUserAccount.accessLevel = targetAccessLevel
			}
			try await targetUserAccount.save(on: req.db)
			// Close any open sockets, keep going if we get an error. Then, delete the user's login token
			// and refresh the user cache.
			try? await req.webSocketStore.handleUserLogout(targetUserAccount.requireID())
			try await Token.query(on: req.db).filter(\.$user.$id == targetUserAccount.requireID()).delete()
			try await req.userCache.updateUser(targetUserAccount.requireID())
		}
		return .ok
	}

	/// ` POST /api/v3/mod/user/ID/tempquarantine/INT`
	///
	/// Moderator only. Applies a tempory quarantine on a user for INT hours, starting immediately. While quarantined, the user may not
	/// create or edit content, but can still read others' content. They can still talk in private Seamail chats.
	///
	/// The primary account and all sub-accounts linked to the given User account are affected by the temporary ban. The passed-in UserID may
	/// be either a primary or sub-account.
	///
	/// - Parameter userID: in URL path.
	/// - Parameter quarantineHours: in URL path. Must be a integer number.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested quarantine was set.
	func applyUserTempQuarantine(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.canModerateUsers() else {
			throw Abort(.badRequest, reason: "This user cannot set access levels.")
		}
		guard let quarantineHours = req.parameters.get("quarantine_length", as: Int.self),
			quarantineHours >= 0, quarantineHours < 200
		else {
			throw Abort(.badRequest, reason: "Invalid temp quarantine length.")
		}
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		guard targetUser.accessLevel < UserAccessLevel.moderator, targetUser.accessLevel != UserAccessLevel.client
		else {
			throw Abort(.badRequest, reason: "You cannot temp quarantine Target user.")
		}
		let allAccounts = try await targetUser.allAccounts(on: req.db)
		if quarantineHours == 0 {
			if targetUser.tempQuarantineUntil != nil {
				allAccounts.forEach { $0.tempQuarantineUntil = nil }
				await allAccounts[0].logIfModeratorAction(.tempQuarantineCleared, user: user, on: req)
			}
		}
		else {
			allAccounts.forEach { $0.tempQuarantineUntil = Date() + Double(quarantineHours) * 60.0 * 60.0 }
			// Note: If user was previously quarantined, and this action changes the length of time, we still
			// log the quarantine action.
			await allAccounts[0].logIfModeratorAction(.tempQuarantine, user: user, on: req)
		}
		for targetUserAccount in allAccounts {
			try await targetUserAccount.save(on: req.db)
		}
		let allAccountIDs = try allAccounts.map { try $0.requireID() }
		try await req.userCache.updateUsers(allAccountIDs)
		return .ok
	}

	// MARK: - Helper Functions

}
