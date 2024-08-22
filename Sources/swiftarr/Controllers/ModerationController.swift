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
		let moderatorAuthGroup = app.tokenRoutes(minAccess: .moderator, path: "api", "v3", "mod")

		// endpoints available for Moderators only
		moderatorAuthGroup.get("reports", use: reportsHandler)
		moderatorAuthGroup.post("reports", ":report_id", "handleall", use: beginProcessingReportsHandler)
		moderatorAuthGroup.post("reports", ":report_id", "closeall", use: closeReportsHandler)
		moderatorAuthGroup.get("moderationlog", use: moderatorActionLogHandler)

		moderatorAuthGroup.get("twarrt", twarrtIDParam, use: twarrtModerationHandler)
		moderatorAuthGroup.post("twarrt", twarrtIDParam, "setstate", modStateParam, use: twarrtSetModerationStateHandler)

		moderatorAuthGroup.get("forumpost", postIDParam, use: forumPostModerationHandler)
		moderatorAuthGroup.post("forumpost", postIDParam, "setstate", modStateParam, use: forumPostSetModerationStateHandler)

		moderatorAuthGroup.get("forum", forumIDParam, use: forumModerationHandler)
		moderatorAuthGroup.post("forum", forumIDParam, "setstate", modStateParam, use: forumSetModerationStateHandler)
		moderatorAuthGroup.post("forum", forumIDParam, "setcategory", categoryIDParam, use: forumSetCategoryHandler)

		moderatorAuthGroup.get("fez", fezIDParam, use: fezModerationHandler)
		moderatorAuthGroup.post("fez", fezIDParam, "setstate", modStateParam, use: fezSetModerationStateHandler)

		moderatorAuthGroup.get("fezpost", fezPostIDParam, use: fezPostModerationHandler)
		moderatorAuthGroup.post("fezpost", fezPostIDParam, "setstate", modStateParam, use: fezPostSetModerationStateHandler)

		moderatorAuthGroup.get("profile", userIDParam, use: profileModerationHandler)
		moderatorAuthGroup.post("profile", userIDParam, "setstate", modStateParam, use: profileSetModerationStateHandler)

		moderatorAuthGroup.get("user", userIDParam, use: userModerationHandler)
		moderatorAuthGroup.post("user", userIDParam, "setaccesslevel", accessLevelParam, use: userSetAccessLevelHandler)
		moderatorAuthGroup.post("user", userIDParam, "tempquarantine", ":quarantine_length", use: applyUserTempQuarantine)
		
		moderatorAuthGroup.get("microkaraoke", "songlist", use: getFullSongList)
		moderatorAuthGroup.get("microkaraoke", "song", mkSongIDParam, use: getSongInfo)
		moderatorAuthGroup.get("microkaraoke", "snippets", mkSongIDParam, use: getSnippetsForModeration)
		moderatorAuthGroup.post("microkaraoke", "snippet", mkSnippetIDParam, "delete", use: deleteSnippet)
		moderatorAuthGroup.delete("microkaraoke", "snippet", mkSnippetIDParam, use: deleteSnippet)
		moderatorAuthGroup.post("microkaraoke", "approve", mkSongIDParam, use: approveSong)

		moderatorAuthGroup.get("personalevent", personalEventIDParam, use: personalEventModerationHandler)
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
	func moderatorActionLogHandler(_ req: Request) async throws -> ModeratorActionLogResponseData {
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
		let query = ModeratorAction.query(on: req.db)
		async let totalActionCount = try query.count()
		async let result = try query.copy().range(start..<(start + limit)).sort(\.$createdAt, .descending).all().map { try ModeratorActionLogData(action: $0, on: req) }
		let response = try await ModeratorActionLogResponseData(
			actions: result,
			paginator: Paginator(total: totalActionCount, start: start, limit: limit)
		)
		return response
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

	/// `GET /api/v3/mod/fez/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a Fez. Works if fez has been deleted. Shows
	/// fez's quarantine and reviewed states.
	///
	/// The `FezModerationData` contains:
	/// * The current fez contents, even if its deleted
	/// * Previous edits of the fez
	/// * Reports against the fez
	/// * The fez's current deletion and moderation status.
	///
	/// - Parameter fezID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezModerationData` containing a bunch of data pertinient to moderating the forum.
	func fezModerationHandler(_ req: Request) async throws -> FezModerationData {
		guard let lfgIDString = req.parameters.get(fezIDParam.paramString), let lfgID = UUID(lfgIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(fezIDParam.paramString) is missing.")
		}
		guard let lfg = try await FriendlyFez.query(on: req.db).filter(\.$id == lfgID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no LFG found for identifier '\(lfgID)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .fez)
			.filter(\.$reportedID == lfgIDString)
			.sort(\.$createdAt, .descending).all()
		let edits = try await lfg.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let ownerHeader = try req.userCache.getHeader(lfg.$owner.id)
		let fezData = try FezData(fez: lfg, owner: ownerHeader)
		let editData: [FezEditLogData] = try edits.map {
			return try FezEditLogData($0, on: req)
		}
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = FezModerationData(
			fez: fezData,
			isDeleted: lfg.deletedAt != nil,
			moderationStatus: lfg.moderationStatus,
			edits: editData,
			reports: reportData
		)
		return modData
	}

	/// ` POST /api/v3/mod/fez/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the fez identified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the current user owns the fez.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func fezSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let lfg = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		try lfg.moderationStatus.setFromParameterString(modState)
		await lfg.logIfModeratorAction(
			ModeratorActionType.setFromModerationStatus(lfg.moderationStatus),
			user: user,
			on: req
		)
		try await lfg.save(on: req.db)
		return .ok
	}

	/// `GET /api/v3/mod/fezpost/:post_id`
	///
	/// Moderator only. Returns info admins and moderators need to review a Fez post. Works if post has been deleted. Shows
	/// fez's quarantine and reviewed states.  Unlike most other content types, Fez Posts cannot be edited (although they may be deleted).
	///
	/// The `FezPostModerationData` contains:
	/// * The current post contents, even if its deleted
	/// * Reports against the post
	/// * The post's current deletion and moderation status.
	///
	/// - Parameter fezPostID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezPostModerationData` containing a bunch of data pertinient to moderating the forum.
	func fezPostModerationHandler(_ req: Request) async throws -> FezPostModerationData {
		guard let postIDString = req.parameters.get(fezPostIDParam.paramString), let postID = Int(postIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(fezPostIDParam.paramString) is missing.")
		}
		guard let lfgPost = try await FezPost.query(on: req.db).with(\.$fez).filter(\.$id == postID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no LFG Post found for identifier '\(postID)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .fezPost)
			.filter(\.$reportedID == postIDString)
			.sort(\.$createdAt, .descending).all()
		let authorHeader = try req.userCache.getHeader(lfgPost.$author.id)
		let fezPostData = try FezPostData(post: lfgPost, author: authorHeader, overrideQuarantine: true)
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let modData = FezPostModerationData(
			fezPost: fezPostData,
			fezID: lfgPost.$fez.id,
			fezType: lfgPost.fez.fezType,
			isDeleted: lfgPost.deletedAt != nil,
			moderationStatus: lfgPost.moderationStatus,
			reports: reportData
		)
		return modData
	}

	/// ` POST /api/v3/mod/fezpost/:post_id/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the fez post identified by ID to the `ContentModerationStatus` in STRING.
	/// Logs the action to the moderator log unless the current user authored the post.
	///
	/// - Parameter fezPostID: in URL path.
	/// - Parameter moderationState: in URL path. Value must match a `ContentModerationStatus` rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func fezPostSetModerationStateHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		let lfgPost = try await FezPost.findFromParameter(fezPostIDParam, on: req)
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
			let targetAccessLevel = UserAccessLevel(fromRawString: accessLevelString),
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

// MARK: Micro Karaoke Moderation
	/// `GET /api/v3/mod/microkaraoke/songlist`
	///
	///  Gets info on all the songs that are in Micro Karaoke, including ones being built.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `[MicroKaraokeCompletedSong]` with info on all the completed songs that can be viewed.
	func getFullSongList(_ req: Request) async throws -> [MicroKaraokeCompletedSong] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can use this endpoint")
		}
		let allSongs = try await MKSong.query(on: req.db).sort(\.$id).all()
		let result = try allSongs.map { song in
			return try MicroKaraokeCompletedSong(from: song, userContributed: false)
		}
		return result
	}

	/// `GET /api/v3/mod/microkaraoke/song/:song_id`
	///
	///  Gets info on a single song in Micro Karaoke..
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MicroKaraokeCompletedSong` with info on the song with the given songID.
	func getSongInfo(_ req: Request) async throws -> MicroKaraokeCompletedSong {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can use this endpoint")
		}
		guard let songID = req.parameters.get(mkSongIDParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Could not get song parameter from URL path")
		}
		guard let song = try await MKSong.query(on: req.db).filter(\.$id == songID).first() else {
			throw Abort(.badRequest, reason: "No song found with this ID.")
		}
		return try MicroKaraokeCompletedSong(from: song, userContributed: false)
	}

	/// `GET /api/v3/mod/microkaraoke/snippets/:song_id`
	///
	///  
	///
	/// - Parameter song_id: The song to get a manifest for.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MicroKaraokeSongManifest` 
	func getSnippetsForModeration(_ req: Request) async throws -> [MicroKaraokeSnippetModeration] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can use this endpoint")
		}
		guard let songID = req.parameters.get(mkSongIDParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Could not get song parameter from URL path")
		}
		guard let _ = try await MKSong.find(songID, on: req.db) else {
			throw Abort(.badRequest, reason: "Could not find a song with this song ID.")
		}
		let songSnippets = try await MKSnippet.query(on: req.db).filter(\.$song.$id == songID).sort(\.$songSnippetIndex).all()
		let result = try songSnippets.map { 
			let author = try req.userCache.getHeader($0.$author.id)
			return try MicroKaraokeSnippetModeration(from: $0, by: author)
		}
		return result
	}
	
	/// `POST /api/v3/mod/microkaraoke/snippet/:snippet_id/delete`
	/// `DELETE /api/v3/mod/microkaraoke/snippet/:snippet_id/`
	///
	///  Moderator only. By design, users may not delete their own submissions.
	///
	/// - Parameter snippet_id: The snippet ID to delete. NOT the snippet index--the index just tells you where the snippet gets inserted into its song.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MicroKaraokeSongManifest` 
	func deleteSnippet(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can use this endpoint")
		}
		guard let snippetID = req.parameters.get(mkSnippetIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Could not get snippetID parameter from URL path")
		}
		if let snippet = try await MKSnippet.query(on: req.db).filter(\.$id == snippetID).with(\.$song).first() {
			snippet.song.isComplete = false
			snippet.song.modApproved = false
			try await snippet.song.save(on: req.db)
			try await snippet.delete(on: req.db)
			try await snippet.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		}
		return .ok
	}
	
	/// `POST /api/v3/mod/microkaraoke/approve/:song_id`
	///
	///  Approve a song for release. Once approved, notifications are sent out to each user that sung a clip in the song.
	///  For this reason, there is not currently an 'unapprove' action, as re-approving would currently re-send all the notifications.
	///  If an approved song contains an objectionable clip, use the mod tools to delete the clip. 
	///
	/// - Parameter song_id: The song ID to approve. 
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: HTTP Status` 
	func approveSong(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can use this endpoint")
		}
		guard let songID = req.parameters.get(mkSongIDParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Could not get snippetID parameter from URL path")
		}
		guard let song = try await MKSong.query(on: req.db).filter(\.$id == songID).first() else {
			throw Abort(.badRequest, reason: "Song not found")
		}
		guard song.isComplete else {
			throw Abort(.badRequest, reason: "Can't approve yet. Song isn't complete.")
		}
		song.modApproved = true
		try await song.save(on: req.db)
		try await song.logIfModeratorAction(.markReviewed, moderatorID: cacheUser.userID, on: req)
		
		// Notify song participants that their song is ready for viewing
		let snippets = try await MKSnippet.query(on: req.db).filter(\.$song.$id == songID).all()
		let singers = Array(Set(snippets.map { $0.$author.id }))
		let infoStr = "A Micro Karaoke song you contributed to is ready for viewing. Go watch the video for song #\(songID)."
		try await addNotifications(users: singers, type: .microKaraokeSongReady(songID), info: infoStr, on: req)

		return .ok
	}

	// MARK: PersonalEvent
	func personalEventModerationHandler(_ req: Request) async throws -> PersonalEventModerationData {
		guard let paramVal = req.parameters.get(personalEventIDParam.paramString), let eventID: UUID = UUID(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(personalEventIDParam.paramString) is missing.")
		}
		guard let personalEvent = try await PersonalEvent.query(on: req.db).filter(\._$id == eventID).withDeleted().first() else {
			throw Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")
		}
		let reports = try await Report.query(on: req.db)
			.filter(\.$reportType == .personalEvent)
			.filter(\.$reportedID == paramVal)
			.sort(\.$createdAt, .descending).all()

		let ownerHeader = try req.userCache.getHeader(personalEvent.$owner.id)
		let participantHeaders = try personalEvent.participantArray.map { try req.userCache.getHeader($0) }
		let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
		let personalEventData = try PersonalEventData(personalEvent, ownerHeader: ownerHeader, participantHeaders: participantHeaders)

		let modData = PersonalEventModerationData(
			personalEvent: personalEventData,
			isDeleted: personalEvent.deletedAt != nil,
			moderationStatus: personalEvent.moderationStatus,
			reports: reportData
		)
		return modData
	}
}
