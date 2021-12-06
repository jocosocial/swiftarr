import Vapor
import Crypto
import FluentSQL

/**
	The collection of `/api/v3/mod/` route endpoints and handler functions related to moderation tasks.
	
	All routes in this group should be restricted to users with moderation priviliges. This controller returns data of 
	a privileged nature, including contents of user reports, edit histories of user content, and log data about moderation actions.
	
	Note that some moderation actions aren't in this file. Most such endpoints have a handler method allowing a user
	to operate on their own content, but also allowing a mod to operate on other users' content. For example, `twarrtUpdateHandler` lets
	a user edit a twarrt they wrote, but also lets mods edit any user's twarrt.
	
	The routes in this controller that return data on various Reportable content types are designed to return everything a Mod might need
	to make moderation decisions, all in one call. In many cases that means calls return multiple array types with no paging or array limits.
	In non-degenerate cases the arrays should less than ~20 elements. Additionally, there are few moderators and they won't be calling these
	methods multiple times per second.	
*/
struct ModerationController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/mod endpoints
		let modRoutes = app.grouped("api", "v3", "mod")
		
		// instantiate authentication middleware
		let requireModMiddleware = RequireModeratorMiddleware()
						 
		// endpoints available for Moderators only
		let moderatorAuthGroup = addTokenAuthGroup(to: modRoutes).grouped([requireModMiddleware])
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
		
		moderatorAuthGroup.get("profile", userIDParam, use: profileModerationHandler)
		moderatorAuthGroup.post("profile", userIDParam, "setstate", modStateParam, use: profileSetModerationStateHandler)

		moderatorAuthGroup.get("user", userIDParam, use: userModerationHandler)
		moderatorAuthGroup.post("user", userIDParam, "setaccesslevel", accessLevelParam, use: userSetAccessLevelHandler)
		moderatorAuthGroup.post("user", userIDParam, "tempquarantine", ":quarantine_length", use: applyUserTempQuarantine)
	}
	
	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.
	
	/// `GET /api/v3/mod/reports`
	///
	/// Retrieves the full `Report` model of all reports.
	///
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: An array of <doc:Report> objects
	func reportsHandler(_ req: Request) throws -> EventLoopFuture<[ReportModerationData]> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		return Report.query(on: req.db).sort(\.$createdAt, .descending).all().flatMapThrowing { reports in
			return try reports.map { try ReportModerationData.init(req: req, report: $0) }
		}
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
	func beginProcessingReportsHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		// TODO: This could benefit from checks that the mod doesn't currently have an actionGroup (that is, already handling a report)
		// and that the reports aren't already being handled by another mod. But, need to think about process--don't want reports getting stuck.
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		return Report.findFromParameter("report_id", on: req).flatMap { report in
			return Report.query(on: req.db)
					.filter(\.$reportType == report.reportType)
					.filter(\.$reportedID == report.reportedID)
					.filter(\.$isClosed == false)
					.all()
					.throwingFlatMap { reports in
				let groupID = UUID()
				var futures: [EventLoopFuture<Void>] = try reports.map { 
					$0.$handledBy.id = try user.requireID()
					$0.actionGroup = groupID
					return $0.save(on: req.db)
				}
				user.actionGroup = groupID
				futures.append(user.save(on: req.db))
				return futures.flatten(on: req.eventLoop).transform(to: .ok)
			}
		}
	}

	/// `POST /api/v3/mod/reports/ID/closeall`
	///
	/// Closes all reports filed against the same piece of content as the given report. That is, if there are several user reports
	/// concerning the same post, this will close all of them.
	/// 
    /// - Parameter reportID: in URL path. Note that this method actually operates on all reports referring to the same content as the indicated report.
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: 200 OK on success
	func closeReportsHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		return Report.findFromParameter("report_id", on: req).flatMap { report in
			return Report.query(on: req.db)
					.filter(\.$reportType == report.reportType)
					.filter(\.$reportedID == report.reportedID)
					.filter(\.$isClosed == false)
					.all()
					.throwingFlatMap { reports in
				var futures: [EventLoopFuture<Void>] = reports.map { 
					$0.isClosed = true
					return $0.save(on: req.db)
				}
				user.actionGroup = nil
				futures.append(user.save(on: req.db))
				return futures.flatten(on: req.eventLoop).transform(to: .ok)
			}
		}
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
	/// - Returns: An array of <doc:ModeratorActionLogData> records.
	func moderatorActionLogHandler(_ req: Request) throws -> EventLoopFuture<[ModeratorActionLogData]> {
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
		return ModeratorAction.query(on: req.db)
				.range(start..<(start + limit))
				.sort(\.$createdAt, .descending).all().flatMapThrowing { logEntries in
			let result = try logEntries.map { try ModeratorActionLogData(action: $0, on: req) }
			return result
		}
	}

	/// `GET /api/v3/mod/twarrt/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a twarrt. Works if twarrt has been deleted. Shows
	/// twarrt's quarantine and reviewed states.
	///
	/// The <doc:TwarrtModerationData> contains:
	/// * The current twarrt contents, even if its deleted
	/// * Previous edits of the twarrt
	/// * Reports against the twarrt
	/// * The twarrt's current deletion and moderation status.
	/// 
    /// - Parameter twarrtID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:TwarrtModerationData> containing a bunch of data pertinient to moderating the twarrt.
	func twarrtModerationHandler(_ req: Request) throws -> EventLoopFuture<TwarrtModerationData> {
		guard let paramVal = req.parameters.get(twarrtIDParam.paramString), let twarrtID = Int(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(twarrtIDParam.paramString) is missing.")
		}
		return Twarrt.query(on: req.db).filter(\._$id == twarrtID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")).flatMap { twarrt in
			return Report.query(on: req.db)
					.filter(\.$reportType == .twarrt)
					.filter(\.$reportedID == paramVal)
					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return twarrt.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
					let twarrtData = try TwarrtData(twarrt: twarrt, creator: authorHeader, isBookmarked: false, 
							userLike: nil, likeCount: 0, overrideQuarantine: true)
					let editData: [PostEditLogData] = try edits.map {
						let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
						return try PostEditLogData(edit: $0, editor: editAuthorHeader)
					}
					let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
					let modData = TwarrtModerationData(twarrt: twarrtData, isDeleted: twarrt.deletedAt != nil, 
							moderationStatus: twarrt.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// `POST /api/v3/mod/twarrt/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the twarrt identified by ID to the <doc:ContentModerationStatus> in STRING.
	/// Logs the action to the moderator log unless the user owns the twarrt. 
	///
    /// - Parameter twarrtID: in URL path.
    /// - Parameter moderationState: in URL path. Value must match a <doc:ContentModerationStatus> rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func twarrtSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		return Twarrt.findFromParameter(twarrtIDParam, on: req).throwingFlatMap { twarrt in
			try twarrt.moderationStatus.setFromParameterString(modState)
			twarrt.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(twarrt.moderationStatus), user: user, on: req)
			return twarrt.save(on: req.db).transform(to: .ok)
		}
	}

	/// `GET /api/v3/mod/forumpost/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a forumPost. Works if forumPost has been deleted. Shows
	/// forumPost's quarantine and reviewed states.
	///
	/// The <doc:ForumPostModerationData> contains:
	/// * The current post contents, even if its deleted
	/// * Previous edits of the post
	/// * Reports against the post
	/// * The post's current deletion and moderation status.
	/// 
    /// - Parameter postID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:ForumPostModerationData> containing a bunch of data pertinient to moderating the post.
	func forumPostModerationHandler(_ req: Request) throws -> EventLoopFuture<ForumPostModerationData> {
		guard let paramVal = req.parameters.get(postIDParam.paramString), let postID = Int(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(postIDParam.paramString) is missing.")
		}
		return ForumPost.query(on: req.db).filter(\._$id == postID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")).flatMap { post in
			return Report.query(on: req.db)
					.filter(\.$reportType == .forumPost)
					.filter(\.$reportedID == paramVal)
					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return post.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let authorHeader = try req.userCache.getHeader(post.$author.id)
					let postData = try PostDetailData(post: post, author: authorHeader, overrideQuarantine: true)
					let editData: [PostEditLogData] = try edits.map {
						let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
						return try PostEditLogData(edit: $0, editor: editAuthorHeader)
					}
					let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
					let modData = ForumPostModerationData(forumPost: postData, isDeleted: post.deletedAt != nil, 
							moderationStatus: post.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// `POST /api/v3/mod/forumpost/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the post idententified by ID to the <doc:ContentModerationStatus> in STRING.
	/// Logs the action to the moderator log unless the user owns the post. 
	///
    /// - Parameter postID: in URL path.
    /// - Parameter moderationState: in URL path. Value must match a <doc:ContentModerationStatus> rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func forumPostSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		return ForumPost.findFromParameter(postIDParam, on: req).throwingFlatMap { forumPost in
			try forumPost.moderationStatus.setFromParameterString(modState)
			forumPost.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(forumPost.moderationStatus), user: user, on: req)
			return forumPost.save(on: req.db).transform(to: .ok)
		}
	}

	/// `GET /api/v3/mod/forum/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a forum. Works if forum has been deleted. Shows
	/// forum's quarantine and reviewed states. Reports against forums should be reserved for reporting problems with the forum's title.
	/// Likely, they'll also get used to report problems with individual posts.
	///
	/// The <doc:ForumModerationData> contains:
	/// * The current forum contents, even if its deleted
	/// * Previous edits of the forum
	/// * Reports against the forum
	/// * The forum's current deletion and moderation status.
	/// 
    /// - Parameter forumID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:ForumModerationData>  containing a bunch of data pertinient to moderating the forum.
	func forumModerationHandler(_ req: Request) throws -> EventLoopFuture<ForumModerationData> {
		guard let forumIDString = req.parameters.get(forumIDParam.paramString), let forumID = UUID(forumIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(forumIDParam.paramString) is missing.")
		}
		return Forum.query(on: req.db).filter(\.$id == forumID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(forumID)'")).flatMap { forum in
			return Report.query(on: req.db)
					.filter(\.$reportType == .forum)
					.filter(\.$reportedID == forumIDString)
					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return forum.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let editData: [ForumEditLogData] = try edits.map {
						return try ForumEditLogData($0, on: req)
					}
					let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
					let modData = try ForumModerationData(forum, edits: editData, reports: reportData, on: req)
					return modData
				}
			}
		}
	}

	/// `POST /api/v3/mod/forum/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the forum idententified by ID to the <doc:ContentModerationStatus> in STRING.
	/// Logs the action to the moderator log unless the current user owns the forum. 
	///
    /// - Parameter forumID: in URL path.
    /// - Parameter moderationState: in URL path. Value must match a <doc:ContentModerationStatus> rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func forumSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
			try forum.moderationStatus.setFromParameterString(modState)
			forum.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(forum.moderationStatus), user: user, on: req)
			return forum.save(on: req.db).transform(to: .ok)
		}
	}
	
	/// `POST /api/v3/mod/forum/:forum_ID/setcategory/:category_ID
	///
	/// Moderator only. Moves the indicated forum into the indicated category. Logs the action to the moderation log.
	func forumSetCategoryHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		return Category.findFromParameter(categoryIDParam, on: req).flatMap { newCategory in
			return Forum.findFromParameter(forumIDParam, on: req, builder: { $0.with(\.$category) }).throwingFlatMap { forum in
				let oldCategory = forum.category
				oldCategory.forumCount -= 1
				newCategory.forumCount += 1
				// Set forum's new parent, also update the forum's accessLevelToView.
				forum.accessLevelToView = newCategory.accessLevelToView
				forum.$category.id = try newCategory.requireID()
				forum.$category.value = newCategory
				return req.db.transaction { db in
					return forum.save(on: db).and(oldCategory.save(on: db).and(newCategory.save(on: db))).map { _ in
						forum.logIfModeratorAction(.move, user: user, on: req)
						return .ok
					}
				}
			}
		}
	}

	/// `GET /api/v3/mod/fez/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a Fez. Works if fez has been deleted. Shows
	/// fez's quarantine and reviewed states.
	///
	/// The <doc:FezModerationData> contains:
	/// * The current fez contents, even if its deleted
	/// * Previous edits of the fez
	/// * Reports against the fez
	/// * The fez's current deletion and moderation status.
	/// 
    /// - Parameter fezID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:FezModerationData> containing a bunch of data pertinient to moderating the forum.
	func fezModerationHandler(_ req: Request) throws -> EventLoopFuture<FezModerationData> {
		guard let fezIDString = req.parameters.get(fezIDParam.paramString), let fezID = UUID(fezIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(fezIDParam.paramString) is missing.")
		}
		return FriendlyFez.query(on: req.db).filter(\.$id == fezID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "no FriendlyFez found for identifier '\(fezID)'")).flatMap { fez in
			return Report.query(on: req.db)
					.filter(\.$reportType == .fez)
					.filter(\.$reportedID == fezIDString)
					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return fez.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let ownerHeader = try req.userCache.getHeader(fez.$owner.id)
					let fezData = try FezData(fez: fez, owner: ownerHeader)
					let editData: [FezEditLogData] = try edits.map {
						return try FezEditLogData($0, on: req)
					}
					let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
					let modData = FezModerationData(fez: fezData, isDeleted: fez.deletedAt != nil, 
							moderationStatus: fez.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// ` POST /api/v3/mod/fez/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the fez idententified by ID to the <doc:ContentModerationStatus> in STRING.
	/// Logs the action to the moderator log unless the current user owns the fez. 
	///
    /// - Parameter fezID: in URL path.
    /// - Parameter moderationState: in URL path. Value must match a <doc:ContentModerationStatus> rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func fezSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { fez in
			try fez.moderationStatus.setFromParameterString(modState)
			fez.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(fez.moderationStatus), user: user, on: req)
			return fez.save(on: req.db).transform(to: .ok)
		}
	}
	
	/// ` GET /api/v3/mod/profile/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a User Profile. The returned info pertains to the user's profile and avatar image --
	/// for example, the web site puts the button allowing mods to edit a user's profile fields on this page.
	///
	/// The <doc:ProfileModerationData> contains:
	/// * The user's profile info and avatar
	/// * Previous edits of the profile and avatar
	/// * Reports against the user's profile
	/// * The user's current  moderation status.
	/// 
    /// - Parameter userID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:ProfileModerationData> containing a bunch of data pertinient to moderating the user's profile.
	func profileModerationHandler(_ req: Request) throws -> EventLoopFuture<ProfileModerationData> {
		guard let targetUserIDString = req.parameters.get(userIDParam.paramString), let targetUserID = UUID(targetUserIDString) else {
			throw Abort(.badRequest, reason: "Request parameter \(userIDParam.paramString) is missing or isn't a UUID.")
		}
		return User.query(on: req.db).filter(\.$id == targetUserID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "no User found for identifier '\(targetUserID)'")).flatMap { targetUser in
			return Report.query(on: req.db)
					.filter(\.$reportType == .userProfile)
					.filter(\.$reportedID == targetUserIDString)
					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return targetUser.$edits.query(on: req.db).sort(\.$createdAt, .descending).all().flatMapThrowing { edits in
					let userProfileData = try UserProfileUploadData(user: targetUser)
					let editData: [ProfileEditLogData] = try edits.map {
						return try ProfileEditLogData($0, on: req)
					}
					let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
					let modData = ProfileModerationData(profile: userProfileData,
							moderationStatus: targetUser.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}
	
	/// ` POST /api/v3/mod/profile/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the profile idententified by userID to the <doc:ContentModerationStatus> in STRING.
	/// Logs the action to the moderator log unless the moderator is changing state on their own profile.. 
	///
    /// - Parameter userID: in URL path.
    /// - Parameter moderationState: in URL path. Value must match a <doc:ContentModerationStatus> rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested moderation status was set.
	func profileSetModerationStateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter `Moderation_State` is missing.")
		}
		return User.findFromParameter(userIDParam, on: req).throwingFlatMap { targetUser in
			try targetUser.moderationStatus.setFromParameterString(modState)
			targetUser.logIfModeratorAction(ModeratorActionType.setFromModerationStatus(targetUser.moderationStatus), user: user, on: req)
			return targetUser.save(on: req.db).transform(to: .ok)
		}
	}
	
	/// ` GET /api/v3/mod/user/ID`
	///
	/// Moderator only. Returns info admins and moderators need to review a User. User moderation in this context means actions taken against the User account
	/// itself,  such as banning and temp-quarantining. These actions don't edit or remove content but prevent the user from creating any more content.
	///
	/// The <doc:UserModerationData> contains:
	/// * UserHeaders for the User's primary account and any sub-accounts.
	/// * Reports against content authored by any of the above accounts, for all content types (twarrt, forum posts, profile, user image)
	/// * The user's current access level.
	/// * Any temp ban the user has.
	/// 
    /// - Parameter userID: in URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:UserModerationData> containing a bunch of data pertinient to moderating the forum.
	func userModerationHandler(_ req: Request) throws -> EventLoopFuture<UserModerationData> {
		return User.findFromParameter(userIDParam, on: req).flatMap { targetUser in
			return targetUser.allAccounts(on: req.db).throwingFlatMap { allAccounts in
				let allUserIDs = try allAccounts.map { try $0.requireID() }
				return Report.query(on: req.db)
						.filter(\.$reportedUser.$id ~~ allUserIDs)
						.sort(\.$createdAt, .descending).all().flatMapThrowing { reports in
					let reportData = try reports.map { try ReportModerationData.init(req: req, report: $0) }
					let modData = try UserModerationData(user: allAccounts[0], subAccounts: Array(allAccounts.dropFirst()), 
							reports: reportData)
					return modData
				}
			}
		}
	}
	
	/// ` POST /api/v3/mod/user/ID/setaccesslevel/STRING`
	///
	/// Moderator only. Sets the accessLevel enum on the user idententified by userID to the <doc:UserAccessLevel> in STRING.
	/// Moderators (and above) cannot use this method to change the access level of other mods (and above). Nor can they use this to
	/// reduce their own access level to non-moderator status.
	///
	/// The primary account and all sub-accounts linked to the given User account are affected by the temporary ban. The passed-in UserID may
	/// be either a primary or sub-account.
	/// 
    /// - Parameter userID: in URL path.
    /// - Parameter accessLevel: in URL path. Value must match a <doc:UserAccessLevel> rawValue.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTPStatus` .ok if the requested access level was set.
	func userSetAccessLevelHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.canModerateUsers() else {
			throw Abort(.badRequest, reason: "This user cannot set access levels.")
		}
		guard let accessLevelString = req.parameters.get(accessLevelParam.paramString), 
				let targetAccessLevel = UserAccessLevel.fromRawString(accessLevelString),
				[.unverified, .banned, .quarantined, .verified].contains(targetAccessLevel) else {
			throw Abort(.badRequest, reason: "Invalid target accessLevel. Must be one of unverified, banned, quarantined, verified.")
		}
		return User.findFromParameter(userIDParam, on: req).throwingFlatMap { targetUser in
			guard targetUser.accessLevel < UserAccessLevel.moderator,
					targetUser.accessLevel != UserAccessLevel.client else {
				throw Abort(.badRequest, reason: "You cannot modify user access level of Target user.")
			}
			return targetUser.allAccounts(on: req.db).throwingFlatMap { allAccounts in
				if let modSettableAccessLevel = ModeratorActionType.setFromAccessLevel(targetAccessLevel) {
					allAccounts[0].logIfModeratorAction(modSettableAccessLevel, user: user, on: req)
				}
				let futures = allAccounts.map { (targetUserAccount) -> EventLoopFuture<Void> in
					targetUserAccount.accessLevel = targetAccessLevel
					return targetUserAccount.save(on: req.db)
				}
				return futures.flatten(on: req.eventLoop).transform(to: .ok)
			}
		}
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
	func applyUserTempQuarantine(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.canModerateUsers() else {
			throw Abort(.badRequest, reason: "This user cannot set access levels.")
		}
		guard let quarantineHours = req.parameters.get("quarantine_length", as: Int.self),
				quarantineHours >= 0, quarantineHours < 200 else {
			throw Abort(.badRequest, reason: "Invalid temp quarantine length.")
		}
		return User.findFromParameter(userIDParam, on: req).throwingFlatMap { targetUser in
			guard targetUser.accessLevel < UserAccessLevel.moderator,
					targetUser.accessLevel != UserAccessLevel.client else {
				throw Abort(.badRequest, reason: "You cannot temp quarantine Target user.")
			}
			return targetUser.allAccounts(on: req.db).throwingFlatMap { allAccounts in
				if quarantineHours == 0 {
					if targetUser.tempQuarantineUntil != nil {
						allAccounts.forEach { $0.tempQuarantineUntil = nil }
						allAccounts[0].logIfModeratorAction(.tempQuarantineCleared, user: user, on: req)
					}
				}
				else { 
					if let endDate = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: quarantineHours, to: Date()) {
						allAccounts.forEach { $0.tempQuarantineUntil = endDate }
					}
					else {
						// Do it the old way
						allAccounts.forEach { $0.tempQuarantineUntil = Date() + Double(quarantineHours) * 60.0 * 60.0 }
					}
					// Note: If user was previously quarantined, and this action changes the length of time, we still
					// log the quarantine action.
					allAccounts[0].logIfModeratorAction(.tempQuarantine, user: user, on: req)
				}
				return allAccounts.map { (targetUserAccount) -> EventLoopFuture<Void> in
					return targetUserAccount.save(on: req.db)
				}.flatten(on: req.eventLoop).transform(to: .ok)
			}
		}
	}
	

	// MARK: - Helper Functions

}
