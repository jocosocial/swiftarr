import Vapor
import Crypto
import FluentSQL

// A set of reports that are all reporting on the same piece of content
struct ReportContentGroup: Codable {
	var reportType: ReportType
	var reportedID: String
	var reportedUser: UserHeader
	var firstReport: ReportModerationData
	var openCount: Int
	var contentURL: String
	var reports: [ReportModerationData]
}
	
/// SiteModController handles a bunch of pages that exist to moderate user content. There's a `.moderator` value in `UserAccessLevel`,
/// but that doesn't mean that everything in this controller is accessible by moderators. 
///
/// The SiteAdminController, by contrast, is responsible for the web front-end to the administration functions, such as server configuration, uploading
/// reg codes/calendars/song lists/game lists, performance monitoring, security, and client management.
struct SiteModController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.	
		//
		// In this case, modRoutes are still Moderator-only. But, one mod could send another a link to one of these pages and it'd work.	
		let modRoutes = getGlobalRoutes(app).grouped(SiteRequireModeratorMiddleware())
		modRoutes.get("reports", use: reportsPageHandler)
		modRoutes.get("moderator", "log",  use: moderatorLogPageHandler)

		modRoutes.get("moderate", "twarrt", twarrtIDParam, use: moderateTwarrtContentPageHandler)
		modRoutes.get("moderate", "forumpost", postIDParam, use: moderateForumPostContentPageHandler)
		modRoutes.get("moderate", "forum", forumIDParam, use: moderateForumContentPageHandler)
		modRoutes.get("moderate", "fez", fezIDParam, use: moderateFezContentPageHandler)
		modRoutes.get("moderate", "fezpost", postIDParam, use: moderateFezPostContentPageHandler)
		modRoutes.get("moderate", "userprofile", userIDParam, use: moderateUserProfileContentPageHandler)
		modRoutes.get("moderate", "user", userIDParam, use: moderateUserContentPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let modPrivateRoutes = getPrivateRoutes(app).grouped(SiteRequireModeratorMiddleware())
		modPrivateRoutes.get("archivedimage", imageIDParam, use: archivedImageHandler)

		modPrivateRoutes.post("twarrt", twarrtIDParam, "setstate", modStateParam, use: setTwarrtModerationStatePostHandler)
		modPrivateRoutes.post("forumpost", postIDParam, "setstate", modStateParam, use: setForumPostModerationStatePostHandler)
		modPrivateRoutes.post("forum", forumIDParam, "setstate", modStateParam, use: setForumModerationStatePostHandler)
		modPrivateRoutes.post("fezpost", postIDParam, "setstate", modStateParam, use: setFezPostModerationStatePostHandler)
		modPrivateRoutes.post("fez", fezIDParam, "setstate", modStateParam, use: setFezModerationStatePostHandler)
		modPrivateRoutes.post("userprofile", userIDParam, "setstate", modStateParam, use: setUserProfileModerationStatePostHandler)

		modPrivateRoutes.post("forum", forumIDParam, "setcategory", categoryIDParam, use: setForumCategoryPostHandler)
		modPrivateRoutes.post("moderate", "user", userIDParam, "setaccesslevel", accessLevelParam, use: setUserAccessLevelPostHandler)
		modPrivateRoutes.post("moderate", "user", userIDParam, "tempquarantine", use: applyTempBanPostHandler)
		modPrivateRoutes.post("moderate", "user", userIDParam, "tempquarantine", "delete", use: removeTempBanPostHandler)

		modPrivateRoutes.post("reports", reportIDParam, "handle",  use: beginProcessingReportsPostHandler)
		modPrivateRoutes.post("reports", reportIDParam, "close",  use: closeReportsPostHandler)
	}
	
	/// `GET /archivedimage/ID`
	///
	/// Moderators only. Returns an image from the image archive (user images that have been replaced by subsequent edits).
	func archivedImageHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let imageID = req.parameters.get(imageIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing image_id parameter.")
		}
		return apiQuery(req, endpoint: "/image/archive/\(imageID)").flatMapThrowing { apiResponse in
			var body = Response.Body.empty
			if let apiResponseBody = apiResponse.body {
				body = Response.Body(buffer: apiResponseBody)
			}
			let response = Response(status: apiResponse.status, headers: apiResponse.headers, body: body)
			return response
		}
	}
	
	/// `GET /reports`
	///
	/// Shows moderators a summary of user-submitted reports, grouped by the content that was reported.
	func reportsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/mod/reports").throwingFlatMap { response in
			let reports = try response.content.decode([ReportModerationData].self)
			let reportedContentArray = generateContentGroups(from: reports)
			let openReportContent = reportedContentArray.compactMap { $0.openCount > 0 ? $0 : nil }
			
			struct ReportsContext : Encodable {
				var trunk: TrunkContext
				var reports: [ReportContentGroup]
				
				init(_ req: Request, reports: [ReportContentGroup]) throws {
					trunk = .init(req, title: "Reports", tab: .none)
					self.reports = reports
				}
			}
			let ctx = try ReportsContext(req, reports: openReportContent)
			return req.view.render("moderation/reports", ctx)			
		}
	}
	
	/// `POST /reports/ID/handle`
	/// 
	/// Marks all reports reporting a specific piece of content as being handled by the current user. While a moderator is handling a report, any 
	/// moderation actions taken get tied to the report being handled. Also, reports being handled are marked as such so other moderators can
	/// hopefully avoid duplicate work. Mods should close reports when they're done to complete the flow.
	func beginProcessingReportsPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let reportID = req.parameters.get(reportIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/reports/\(reportID)/handleall", method: .POST).map { response in
			return response.status	
		}
	}
	
	/// `POST /reports/ID/close`
	///
	/// Sets the state of all reports in a group to Closed. Although it takes an ID of one report, it finds all reports that refer to the same pirce
	/// of content, and closes all of them.
	func closeReportsPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let reportID = req.parameters.get(reportIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/reports/\(reportID)/closeall", method: .POST).map { response in
			return response.status	
		}
	}

	/// `GET /moderator/log`
	///
	/// Shows a page with a table of all moderator actions. 
	func moderatorLogPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/mod/moderationlog").throwingFlatMap { response in
			let logData = try response.content.decode([ModeratorActionLogData].self)
			struct LogContext : Encodable {
				var trunk: TrunkContext
				var log: [ModeratorActionLogData]
				
				init(_ req: Request, log: [ModeratorActionLogData]) throws {
					trunk = .init(req, title: "Moderator Action Log", tab: .none)
					self.log = log
				}
			}
			let ctx = try LogContext(req, log: logData)
			return req.view.render("moderation/moderatorActionLog", ctx)
		}
	}

	///	`GET /moderate/twarrt/ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The twarrt that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	func moderateTwarrtContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/twarrt/\(twarrtID)").throwingFlatMap { response in
			let modData = try response.content.decode(TwarrtModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: TwarrtModerationData
				var firstReport: ReportModerationData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: TwarrtModerationData) throws {
					trunk = .init(req, title: "Reports", tab: .none)
					self.modData = modData
					firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
					finalEditAuthor = modData.edits.last?.author
					if self.modData.edits.count > 1 {
						for index in (0...self.modData.edits.count - 2).reversed() {
							self.modData.edits[index + 1].author = self.modData.edits[index].author
							self.modData.edits[index + 1].author.username = "\(self.modData.edits[index + 1].author.username) edited to:"
						}
					}
					if self.modData.edits.count > 0 {
						self.modData.edits[0].author = modData.twarrt.author
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
						
					}
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/twarrtView", ctx)
		}
	}
	
	///	`POST /moderate/twarrt/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given twarrt. Moderation states include "locked" and "quarantined", as well as a few others.
	func setTwarrtModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/twarrt/\(twarrtID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}

	/// `GET /moderate/forumpost/:post_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The post that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// * 
	func moderateForumPostContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/forumpost/\(postID)").throwingFlatMap { response in
			let modData = try response.content.decode(ForumPostModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: ForumPostModerationData
				var firstReport: ReportModerationData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: ForumPostModerationData) throws {
					trunk = .init(req, title: "Reports", tab: .none)
					self.modData = modData
					firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
					finalEditAuthor = modData.edits.last?.author
					if self.modData.edits.count > 1 {
						for index in (0...self.modData.edits.count - 2).reversed() {
							self.modData.edits[index + 1].author = self.modData.edits[index].author
							self.modData.edits[index + 1].author.username = "\(self.modData.edits[index + 1].author.username) edited to:"
						}
					}
					if self.modData.edits.count > 0 {
						self.modData.edits[0].author = modData.forumPost.author
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
						
					}
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/forumPostView", ctx)
		}
	}
	
	///	`POST /moderate/forumpost/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given forum post. Moderation states include "locked" and "quarantined", as well as a few others.
	func setForumPostModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/forumPost/\(postID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
	
	/// `GET /moderate/forum/:forum_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The forum that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// * 
	func moderateForumContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/forum/categories").flatMap { categoriesResponse in
			return apiQuery(req, endpoint: "/mod/forum/\(forumID)").throwingFlatMap { response in
				let modData = try response.content.decode(ForumModerationData.self)
				let categoryData = try categoriesResponse.content.decode([CategoryData].self)
				struct ReportContext : Encodable {
					var trunk: TrunkContext
					var modData: ForumModerationData
					var firstReport: ReportModerationData?
					var finalEditAuthor: UserHeader?
					var finalEditPrevCategory: String?
					var currentCategory: String?
					var categories: [CategoryData]
					
					init(_ req: Request, modData: ForumModerationData, categories: [CategoryData]) throws {
						let categoryDict = categories.reduce(into: [:]) { $0[$1.categoryID] = $1 }
						trunk = .init(req, title: "Reports", tab: .none)
						self.modData = modData
						self.categories = categories
						firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
						finalEditAuthor = modData.edits.last?.author
						if let prevCat = modData.edits.last?.categoryID {
							finalEditPrevCategory = categoryDict[prevCat]?.title ?? "unknown category"
						}
						currentCategory = categoryDict[modData.categoryID]?.title ?? "unknown"
						if self.modData.edits.count > 1 {
							for index in (0...self.modData.edits.count - 2).reversed() {
								self.modData.edits[index + 1].author = self.modData.edits[index].author
								if let oldCat = self.modData.edits[index].categoryID {
									let oldCatTitle = categoryDict[oldCat]?.title ?? "unknown category"
									self.modData.edits[index + 1].author.username = 
											"\(self.modData.edits[index + 1].author.username) changed the category from \"\(oldCatTitle)\""
								}
								else {
									self.modData.edits[index + 1].author.username = "\(self.modData.edits[index + 1].author.username) edited to:"
								}
							}
						}
						if self.modData.edits.count > 0 {
							self.modData.edits[0].author = modData.creator
							self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
						}
					}
				}
				let ctx = try ReportContext(req, modData: modData, categories: categoryData)
				return req.view.render("moderation/forumView", ctx)
			}
		}
	}
	
	///	`POST /moderate/forum/:forum_ID/move/:category_ID`
	///
	/// Moves a forum thread into a new category. Once moved, the thread will have the same restrictions on viewability as other threads in the destination category.
	/// This means we could make a 'forum dumpster' category that was mod-only and mods could move awful forum threads into it, and later review individual posts
	/// and hand out bans. The utility of this approach is: without this we don't have a way to get a forum out of circulation without deleting the whole forum.
	func setForumCategoryPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum ID parameter.")
		}
		guard let categoryID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing category ID parameter.")
		}
		return apiQuery(req, endpoint: "/mod/forum/\(forumID)/setcategory/\(categoryID)", method: .POST).map { response in
			return response.status
		}
	}
	
	///	`POST /moderate/forum/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given forum. Moderation states include "locked" and "quarantined", as well as a few others.
	func setForumModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/forum/\(forumID)/setcategory/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
	
	/// `GET /moderate/fez/:fez_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The Fez that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// * 
	func moderateFezContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/fez/\(fezID)").throwingFlatMap { response in
			let modData = try response.content.decode(FezModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: FezModerationData
				var firstReport: ReportModerationData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: FezModerationData) throws {
					trunk = .init(req, title: "Fez Moderation", tab: .none)
					self.modData = modData
					firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
					finalEditAuthor = modData.edits.last?.author
					if self.modData.edits.count > 1 {
						for index in (0...self.modData.edits.count - 2).reversed() {
							self.modData.edits[index + 1].author = self.modData.edits[index].author
							self.modData.edits[index + 1].author.username = "\(self.modData.edits[index + 1].author.username) edited to:"
						}
					}
					if self.modData.edits.count > 0 {
						self.modData.edits[0].author = modData.fez.owner
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
					}
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/fezView", ctx)
		}
	}
	
	///	`POST /moderate/fez/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given fez. Moderation states include "locked" and "quarantined", as well as a few others.
	func setFezModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/fez/\(fezID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
	
	/// `GET /moderate/fezpost/:fezpost_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The Fez Post that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// * 
	func moderateFezPostContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezPostID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/fezpost/\(fezPostID)").throwingFlatMap { response in
			let modData = try response.content.decode(FezPostModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: FezPostModerationData
				var firstReport: ReportModerationData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: FezPostModerationData) throws {
					trunk = .init(req, title: "Fez Post Moderation", tab: .none)
					self.modData = modData
					firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/fezPostView", ctx)
		}
	}

	///	`POST /moderate/fezpost/:post_ID/setstate/STRING`
	///
	/// Sets the moderation state of the given fez. Moderation states include "locked" and "quarantined", as well as a few others.
	func setFezPostModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/fezpost/\(postID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
	
	/// `GET /moderate/userprofile/ID`
	/// 
	/// Info from user's profile. Previous profile versions, reports against the user's profile fields or avatar image.
	func moderateUserProfileContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/profile/\(userID)").throwingFlatMap { response in
			let modData = try response.content.decode(ProfileModerationData.self)
			struct UserModContext : Encodable {
				var trunk: TrunkContext
				var modData: ProfileModerationData
				var firstReport: ReportModerationData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: ProfileModerationData) throws {
					trunk = .init(req, title: "User Profile Moderation", tab: .none)
					self.modData = modData
					firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
					finalEditAuthor = modData.edits.last?.author
					if self.modData.edits.count > 1 {
						for index in (0...self.modData.edits.count - 2).reversed() {
							self.modData.edits[index + 1].author = self.modData.edits[index].author
							self.modData.edits[index + 1].author.username = "\(self.modData.edits[index + 1].author.username) edited to:"
						}
					}
					if self.modData.edits.count > 0 {
						if let firstEditor = modData.profile.header {
							self.modData.edits[0].author = firstEditor
						}
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
					}
				}
			}
			let ctx = try UserModContext(req, modData: modData)
			return req.view.render("moderation/profileView", ctx)
		}
	}
	
	///	`POST /moderate/userprofile/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given user's profile. ID is a userID UUID.. Moderation states include "locked" and "quarantined", as well as a few others.
	/// Again: Setting the state to "locked" prevents the user from modifying their profile and avatar, but doesn't otherwise constrain them. 
	/// Similarly, quarantine state prevents others from seeing the avatar and profile field text, but doesn't prevent the user from posting content.
	func setUserProfileModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/profile/\(userID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
	
	/// `GET /moderate/user/ID`
	/// 
	/// Shows the User Moderation page, which has the user's accessLevel controls, temp banning, and a list of all reports
	/// filed against any of this user's content.
	func moderateUserContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/user/\(userID)").throwingFlatMap { response in
			let modData = try response.content.decode(UserModerationData.self)
			struct UserModContext : Encodable {
				var trunk: TrunkContext
				var modData: UserModerationData
				var accessLevelString: String
				var reportGroups: [ReportContentGroup]
				
				init(_ req: Request, modData: UserModerationData) throws {
					trunk = .init(req, title: "User Moderation", tab: .none)
					self.modData = modData
					accessLevelString = modData.accessLevel.visibleName()
					reportGroups = generateContentGroups(from: modData.reports)
				}
			}
			let ctx = try UserModContext(req, modData: modData)
			return req.view.render("moderation/userView", ctx)
		}
	}
	
	///	`POST /moderate/user/ID/setaccesslevel/STRING`
	///
	/// Sets the moderation state of the given user's profile. ID is a userID UUID.. Moderation states include "locked" and "quarantined", as well as a few others.
	/// Again: Setting the state to "locked" prevents the user from modifying their profile and avatar, but doesn't otherwise constrain them. 
	/// Similarly, quarantine state prevents others from seeing the avatar and profile field text, but doesn't prevent the user from posting content.
	func setUserAccessLevelPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing userID parameter.")
		}
		guard let accessLevel = req.parameters.get(accessLevelParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing access level parameter.")
		}
		return apiQuery(req, endpoint: "/mod/user/\(userID)/setaccesslevel/\(accessLevel)", method: .POST).map { response in
			return response.status
		}
	}
	
	///	`POST /moderate/user/ID/tempquarantine`
	///
	/// Applies a temporary quarantine to the user given by ID. While quarantined, the user may not create or edit content, 
	/// but can still log in and read others' content. They can still talk in private Seamail chats. They cannot edit their profile or change their avatar image.
	/// Temp quarantines effectively change the user's accessLevel to `.quarantined` for the duration, after which the user's accessLevel reverts
	/// to what it was previously.
	func applyTempBanPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing userID parameter.")
		}
		struct TempBanFormData: Content {
			var banlength: Int
		}
		let postStruct = try req.content.decode(TempBanFormData.self)
		return apiQuery(req, endpoint: "/mod/user/\(userID)/tempquarantine/\(postStruct.banlength)", method: .POST).map { response in
			return response.status
		}
	}
	
	
	///	`POST /moderate/user/ID/tempquarantine/delete`
	///
	/// Applies a temporary quarantine to the user given by ID. While quarantined, the user may not create or edit content, 
	/// but can still log in and read others' content. They can still talk in private Seamail chats. They cannot edit their profile or change their avatar image.
	/// Temp quarantines effectively change the user's accessLevel to `.quarantined` for the duration, after which the user's accessLevel reverts
	/// to what it was previously.
	func removeTempBanPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing userID parameter.")
		}
		return apiQuery(req, endpoint: "/mod/user/\(userID)/tempquarantine/0", method: .POST).map { response in
			return response.status
		}
	}
	
}
	
// MARK: - Utilities

// Groups reports that are reporting on the same thing; returns `ReportContentGroup` array with one 
// entry per reported content
func generateContentGroups(from reports: [ReportModerationData]) -> [ReportContentGroup] {
	var reportedContentArray = [ReportContentGroup]()
	for report in reports {
		if let index = reportedContentArray.firstIndex(where: { report.reportedID == $0.reportedID && report.type == $0.reportType }) {
			var content = reportedContentArray[index]
			content.openCount += report.isClosed ? 0 : 1
			if content.firstReport.creationTime > report.creationTime {
				content.firstReport = report
			}
			content.reports.append(report)
			reportedContentArray[index] = content
			continue
		}
		
		var contentURL: String
		switch report.type {
			case .twarrt: 		contentURL = "/moderate/twarrt/\(report.reportedID)"
			case .forumPost: 	contentURL = "/moderate/forumpost/\(report.reportedID)"
			case .forum: 		contentURL = "/moderate/forum/\(report.reportedID)"
			case .fez: 			contentURL = "/moderate/fez/\(report.reportedID)"
			case .fezPost: 		contentURL = "/moderate/fezpost/\(report.reportedID)"
			case .userProfile: 	contentURL = "/moderate/userprofile/\(report.reportedID)"
		}
		var newGroup = ReportContentGroup(reportType: report.type, reportedID: report.reportedID, reportedUser: report.reportedUser, 
				firstReport: report, openCount: 0, contentURL: contentURL, reports: [report])
		newGroup.openCount += report.isClosed ? 0 : 1
		reportedContentArray.append(newGroup)
	}
	return reportedContentArray
}


