import Vapor
import Crypto
import FluentSQL

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

		modRoutes.get("moderate", "twarrt", twarrtIDParam, use: moderateTwarrtContentPageHandler)
		modRoutes.get("moderate", "forumpost", postIDParam, use: moderateForumPostContentPageHandler)
		modRoutes.get("moderate", "forum", forumIDParam, use: moderateForumContentPageHandler)
		modRoutes.get("moderate", "fez", fezIDParam, use: moderateFezContentPageHandler)

		modRoutes.post("twarrt", twarrtIDParam, "setstate", modStateParam, use: setTwarrtModerationStatePostHandler)
		modRoutes.post("forumpost", postIDParam, "setstate", modStateParam, use: setForumPostModerationStatePostHandler)
		modRoutes.post("forum", forumIDParam, "setstate", modStateParam, use: setForumModerationStatePostHandler)
		modRoutes.post("fez", fezIDParam, "setstate", modStateParam, use: setFezModerationStatePostHandler)

		modRoutes.post("reports", reportIDParam, "handle",  use: beginProcessingReportsPostHandler)
		modRoutes.post("reports", reportIDParam, "close",  use: closeReportsPostHandler)
	}
	
	struct ReportContentGroup: Codable {
		var reportType: ReportType
		var reportedID: String
		var reportedUser: UserHeader
		var firstReportTime: Date
		var openCount: Int
		var contentURL: String
		var reports: [ReportAdminData]
	}
	
	func reportsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	return apiQuery(req, endpoint: "/mod/reports").throwingFlatMap { response in
			let reports = try response.content.decode([ReportAdminData].self)
			
			var reportedContentArray = [ReportContentGroup]()
			reportLoop: for report in reports {
				for var content in reportedContentArray {
					if report.reportedID == content.reportedID && report.type == content.reportType {
						content.openCount += report.isClosed ? 0 : 1
						if content.firstReportTime < report.creationTime {
							content.firstReportTime = report.creationTime
						}
						content.reports.append(report)
						break reportLoop
					}
				}
				var contentURL: String
				switch report.type {
					case .twarrt: 		contentURL = "moderate/twarrt/\(report.reportedID)"
					case .forumPost: 	contentURL = "moderate/forumpost/\(report.reportedID)"
					case .forum: 		contentURL = "moderate/forum/\(report.reportedID)"
					case .fez: 			contentURL = "moderate/fez/\(report.reportedID)"
					case .fezPost: 		contentURL = "moderate/fezpost/\(report.reportedID)"
					case .user: 		contentURL = "moderate/user/\(report.reportedID)"
				}
				var newGroup = ReportContentGroup(reportType: report.type, reportedID: report.reportedID, reportedUser: report.reportedUser, 
						firstReportTime: Date(), openCount: 0, contentURL: contentURL, reports: [report])
				newGroup.openCount += report.isClosed ? 0 : 1
				newGroup.firstReportTime = report.creationTime
				reportedContentArray.append(newGroup)
			}
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
		
	func beginProcessingReportsPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let reportID = req.parameters.get(reportIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/mod/reports/\(reportID)/handleall", method: .POST).map { response in
			return response.status	
		}
	}
	
	func closeReportsPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let reportID = req.parameters.get(reportIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/mod/reports/\(reportID)/closeall", method: .POST).map { response in
			return response.status	
		}
	}

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

	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The twarrt that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// * 
	func moderateTwarrtContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/mod/twarrt/\(twarrtID)").throwingFlatMap { response in
			let modData = try response.content.decode(TwarrtModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: TwarrtModerationData
				var firstReport: ReportAdminData?
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
	
	func setTwarrtModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
	    guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
	    guard let modState = req.parameters.get(modStateParam.paramString) else {
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
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/mod/forumpost/\(postID)").throwingFlatMap { response in
			let modData = try response.content.decode(ForumPostModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: ForumPostModerationData
				var firstReport: ReportAdminData?
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
	
	func setForumPostModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
	    guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
	    guard let modState = req.parameters.get(modStateParam.paramString) else {
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
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/mod/forum/\(forumID)").throwingFlatMap { response in
			let modData = try response.content.decode(ForumModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: ForumModerationData
				var firstReport: ReportAdminData?
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
						self.modData.edits[0].author = modData.forum.creator
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
					}
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/forumView", ctx)
		}
	}
	
	func setForumModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
	    guard let forumID = req.parameters.get(forumIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
	    guard let modState = req.parameters.get(modStateParam.paramString) else {
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
    	guard let fezID = req.parameters.get(fezIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/mod/fez/\(fezID)").throwingFlatMap { response in
			let modData = try response.content.decode(FezModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: FezModerationData
				var firstReport: ReportAdminData?
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: FezModerationData) throws {
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
						self.modData.edits[0].author = modData.fez.owner
						self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
					}
				}
			}
			let ctx = try ReportContext(req, modData: modData)
			return req.view.render("moderation/fezView", ctx)
		}
	}
	
	func setFezModerationStatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/mod/fez/\(fezID)/setstate/\(modState)", method: .POST).map { response in
			return response.status
		}
	}
}
