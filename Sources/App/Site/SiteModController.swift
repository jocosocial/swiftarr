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
		modRoutes.get("moderate", "twarrt", twarrtIDParam,  use: moderateTwarrtContentPageHandler)
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
    	return apiQuery(req, endpoint: "/admin/reports").throwingFlatMap { response in
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
					case .twarrt: contentURL = "moderate/twarrt/\(report.reportedID)"
					case .forumPost: contentURL = "moderate/forumpost/\(report.reportedID)"
					case .forum: contentURL = "moderate/forum/\(report.reportedID)"
					case .fezPost: contentURL = "moderate/fezPost/\(report.reportedID)"
					case .user: contentURL = "moderate/user/\(report.reportedID)"
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
					trunk = .init(req, title: "Reports")
					self.reports = reports
				}
			}
			let ctx = try ReportsContext(req, reports: openReportContent)
			return req.view.render("moderation/reports", ctx)			
    	}
	}
		
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The twarrt/post/forum/user/seamail that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// * 
	func moderateTwarrtContentPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/admin/twarrt/\(twarrtID)").throwingFlatMap { response in
			let modData = try response.content.decode(TwarrtModerationData.self)
			struct ReportContext : Encodable {
				var trunk: TrunkContext
				var modData: TwarrtModerationData
				var finalEditAuthor: UserHeader?
				
				init(_ req: Request, modData: TwarrtModerationData) throws {
					trunk = .init(req, title: "Reports")
					self.modData = modData
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

}
