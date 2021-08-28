import Vapor
import Crypto
import FluentSQL

/**
	The collection of `/api/v3/mod/` route endpoints and handler functions related to moderation tasks..
	
	All routes in this group should be restricted to users with moderation priviliges. This controller returns data of 
	a privledged nature, including contents of user reports, edit histories of user content, and log data about moderation actions.
	
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

		moderatorAuthGroup.get("fez", fezIDParam, use: fezModerationHandler)
		moderatorAuthGroup.post("fez", fezIDParam, "setstate", modStateParam, use: fezSetModerationStateHandler)
		
		moderatorAuthGroup.get("profile", userIDParam, use: profileModerationHandler)
		moderatorAuthGroup.post("profile", userIDParam, "setstate", modStateParam, use: profileSetModerationStateHandler)
	}
	
	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.
	
	/// `GET /api/v3/mod/reports`
	///
	/// Retrieves the full `Report` model of all reports.
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: `[Report]`.
	func reportsHandler(_ req: Request) throws -> EventLoopFuture<[ReportAdminData]> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Moderators only")
		}
		return Report.query(on: req.db).sort(\.$createdAt, .descending).all().flatMapThrowing { reports in
			return try reports.map { try ReportAdminData.init(req: req, report: $0) }
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
	/// Retrieves ModeratorAction recoreds. These records are a log of Mods using their Mod powers.
	/// 
	/// URL Query Parameters:
	/// * `?start=INT` - the offset from the anchor to start. Offset only counts twarrts that pass the filters.
	/// * `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50
	/// 
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: 403 error if the user is not an admin.
	/// - Returns: `[Report]`.
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

	/// ` GET /api/v3/mod/twarrt/ID`
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
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `TwarrtModerationData` containing a bunch of data pertinient to moderating the twarrt.
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
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = TwarrtModerationData(twarrt: twarrtData, isDeleted: twarrt.deletedAt != nil, 
							moderationStatus: twarrt.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// ` POST /api/v3/mod/twarrt/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the twarrt idententified by ID to the `ModerationState` in STRING.
	/// Logs the action to the moderator log unless the user owns the twarrt. 
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
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

	/// ` GET /api/v3/mod/forumpost/ID`
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
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ForumPostModerationData` containing a bunch of data pertinient to moderating the post.
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
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = ForumPostModerationData(forumPost: postData, isDeleted: post.deletedAt != nil, 
							moderationStatus: post.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// ` POST /api/v3/mod/forumpost/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the post idententified by ID to the `ModerationState` in STRING.
	/// Logs the action to the moderator log unless the user owns the post. 
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
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

	/// ` GET /api/v3/mod/forum/ID`
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
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ForumModerationData` containing a bunch of data pertinient to moderating the forum.
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
					let forumData = try ForumAdminData(forum, on: req)
					let editData: [ForumEditLogData] = try edits.map {
						return try ForumEditLogData($0, on: req)
					}
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = ForumModerationData(forum: forumData, isDeleted: forum.deletedAt != nil, 
							moderationStatus: forum.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// ` POST /api/v3/mod/forum/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the forum idententified by ID to the `ModerationState` in STRING.
	/// Logs the action to the moderator log unless the current user owns the forum. 
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
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

	/// ` GET /api/v3/mod/fez/ID`
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
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezModerationData` containing a bunch of data pertinient to moderating the forum.
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
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = FezModerationData(fez: fezData, isDeleted: fez.deletedAt != nil, 
							moderationStatus: fez.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}

	/// ` POST /api/v3/mod/fez/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the fez idententified by ID to the `ModerationState` in STRING.
	/// Logs the action to the moderator log unless the current user owns the fez. 
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
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
	/// The `ProfileModerationData` contains:
	/// * The user's profile info and avatar
	/// * Previous edits of the profile and avatar
	/// * Reports against the user's profile
	/// * The user's current  moderation status.
	/// 
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezModerationData` containing a bunch of data pertinient to moderating the forum.
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
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = ProfileModerationData(profile: userProfileData, accessLevel: targetUser.accessLevel,
							moderationStatus: targetUser.moderationStatus, edits: editData, reports: reportData)
					return modData
				}
			}
		}
	}
	
	/// ` POST /api/v3/mod/profile/ID/setstate/STRING`
	///
	/// Moderator only. Sets the moderation state enum on the profile idententified by userID to the `ModerationState` in STRING.
	/// Logs the action to the moderator log unless the moderator is changing state on their own profile.. 
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
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

	// MARK: - Helper Functions

}
