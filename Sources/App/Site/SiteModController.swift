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
//		let globalRoutes = getGlobalRoutes(app)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
		let modRoutes = privateRoutes.grouped(RequireModeratorMiddleware())
		modRoutes.get("reports", use: reportsPageHandler)
		modRoutes.get("moderator", "log",  use: moderatorLogPageHandler)
		modRoutes.get("archivedimage", imageIDParam, use: archivedImageHandler)

		modRoutes.get("moderate", "twarrt", twarrtIDParam, use: moderateTwarrtContentPageHandler)
		modRoutes.get("moderate", "forumpost", postIDParam, use: moderateForumPostContentPageHandler)
		modRoutes.get("moderate", "forum", forumIDParam, use: moderateForumContentPageHandler)
		modRoutes.get("moderate", "fez", fezIDParam, use: moderateFezContentPageHandler)
		modRoutes.get("moderate", "userprofile", userIDParam, use: moderateUserProfileContentPageHandler)
		modRoutes.get("moderate", "user", userIDParam, use: moderateUserContentPageHandler)

		modRoutes.post("twarrt", twarrtIDParam, "setstate", modStateParam, use: setTwarrtModerationStatePostHandler)
		modRoutes.post("forumpost", postIDParam, "setstate", modStateParam, use: setForumPostModerationStatePostHandler)
		modRoutes.post("forum", forumIDParam, "setstate", modStateParam, use: setForumModerationStatePostHandler)
		modRoutes.post("fez", fezIDParam, "setstate", modStateParam, use: setFezModerationStatePostHandler)
		modRoutes.post("userprofile", userIDParam, "setstate", modStateParam, use: setUserProfileModerationStatePostHandler)
		modRoutes.post("moderate", "user", userIDParam, "setaccesslevel", accessLevelParam, use: setUserAccessLevelPostHandler)
		modRoutes.post("moderate", "user", userIDParam, "tempquarantine", use: applyTempBanPostHandler)
		modRoutes.post("moderate", "user", userIDParam, "tempquarantine", "delete", use: removeTempBanPostHandler)

		modRoutes.post("reports", reportIDParam, "handle",  use: beginProcessingReportsPostHandler)
		modRoutes.post("reports", reportIDParam, "close",  use: closeReportsPostHandler)
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
//			var reportedContentArray = [ReportContentGroup]()
//			reportLoop: for report in reports {
//				for var content in reportedContentArray {
//					if report.reportedID == content.reportedID && report.type == content.reportType {
//						content.openCount += report.isClosed ? 0 : 1
//						if content.firstReportTime < report.creationTime {
//							content.firstReportTime = report.creationTime
//						}
//						content.reports.append(report)
//						break reportLoop
//					}
//				}
//				var contentURL: String
//				switch report.type {
//					case .twarrt: 		contentURL = "moderate/twarrt/\(report.reportedID)"
//					case .forumPost: 	contentURL = "moderate/forumpost/\(report.reportedID)"
//					case .forum: 		contentURL = "moderate/forum/\(report.reportedID)"
//					case .fez: 			contentURL = "moderate/fez/\(report.reportedID)"
//					case .fezPost: 		contentURL = "moderate/fezpost/\(report.reportedID)"
//					case .userProfile: 	contentURL = "moderate/userprofile/\(report.reportedID)"
//				}
//				var newGroup = ReportContentGroup(reportType: report.type, reportedID: report.reportedID, reportedUser: report.reportedUser, 
//						firstReportTime: Date(), openCount: 0, contentURL: contentURL, reports: [report])
//				newGroup.openCount += report.isClosed ? 0 : 1
//				newGroup.firstReportTime = report.creationTime
//				reportedContentArray.append(newGroup)
//			}
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
		return apiQuery(req, endpoint: "/mod/forum/\(forumID)").throwingFlatMap { response in
			let modData = try response.content.decode(ForumModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: ForumModerationData
				var firstReport: ReportModerationData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: ForumModerationData) throws {
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
						self.modData.edits[0].author = modData.creator
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
					}
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/forumView", ctx)
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
		return apiQuery(req, endpoint: "/mod/forum/\(forumID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
	
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
	reportLoop: for report in reports {
		for var content in reportedContentArray {
			if report.reportedID == content.reportedID && report.type == content.reportType {
				content.openCount += report.isClosed ? 0 : 1
				if content.firstReport.creationTime > report.creationTime {
					content.firstReport = report
				}
				content.reports.append(report)
				break reportLoop
			}
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


