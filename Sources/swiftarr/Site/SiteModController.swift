import Crypto
import FluentSQL
import Vapor

// A set of reports that are all reporting on the same piece of content
struct ReportContentGroup: Codable {
	var reportType: ReportType
	var reportedID: String
	var reportedUser: UserHeader
	var firstReport: ReportModerationData
	var openCount: Int
	var handledBy: UserHeader?
	var contentURL: String
	var reports: [ReportModerationData]
}

// For the Open Reports and Closed Reports views
struct ReportsContext: Encodable {
	var trunk: TrunkContext
	var reports: [ReportContentGroup]

	init(_ req: Request, reports: [ReportContentGroup], isClosed: Bool = false) throws {
		trunk = .init(req, title: isClosed ? "Closed Reports" : "Reports", tab: .moderator)
		self.reports = reports
	}
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
		modRoutes.get("moderator", use: moderatorRootPageHandler).destination("the moderator root page")
		modRoutes.get("reports", use: reportsPageHandler).destination("the user reports page")
		modRoutes.get("reports", "closed", use: closedReportsPageHandler).destination("the list of closed user reports")
		modRoutes.get("moderator", "log", use: moderatorLogPageHandler).destination("the moderator log")
		modRoutes.get("moderator", "seamail", use: moderatorSeamailPageHandler).destination("seamails to @moderator")
		modRoutes.get("moderator", "guide", use: moderatorGuidePageHandler).destination("the moderator guide")

		modRoutes.get("moderate", "twarrt", twarrtIDParam, use: moderateTwarrtContentPageHandler).destination("the moderation page for this twarrt")
		modRoutes.get("moderate", "forumpost", postIDParam, use: moderateForumPostContentPageHandler).destination("the moderation page for this forum post")
		modRoutes.get("moderate", "forum", forumIDParam, use: moderateForumContentPageHandler).destination("the moderation page for this forum")
		modRoutes.get("moderate", "lfg", fezIDParam, use: moderateFezContentPageHandler).destination("the moderation page for this lfg")
		modRoutes.get("moderate", "fezpost", postIDParam, use: moderateFezPostContentPageHandler).destination("the moderation page for thie LFG post")
		modRoutes.get("moderate", "microkaraoke", use: getMicroKaraokeSongsPageHandler).destination("the moderation page for microkaraoke songs")
		modRoutes.get("moderate", "microkaraoke", "song", mkSongIDParam, use: moderateMicroKaraokeSongPageHandler).destination("the moderation page for this microkaraoke song")
		modRoutes.get("moderate", "userprofile", userIDParam, use: moderateUserProfileContentPageHandler).destination("the moderation page for this user profile")
		modRoutes.get("moderate", "user", userIDParam, use: moderateUserContentPageHandler).destination("the moderation page for this user")
		modRoutes.get("moderate", "photostream", streamPhotoParam, use: moderatePhotostreamPhotoPageHandler).destination("the moderation page for the photostream")
		modRoutes.get("moderate", "personalevent", personalEventIDParam, use: moderatePersonalEventPageHandler).destination("the moderation page for this personalevent")

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let modPrivateRoutes = getPrivateRoutes(app).grouped(SiteRequireModeratorMiddleware())
		modPrivateRoutes.get("archivedimage", imageIDParam, use: archivedImageHandler)

		modPrivateRoutes.post("twarrt", twarrtIDParam, "setstate", modStateParam, use: setTwarrtModerationStatePostHandler)
		modPrivateRoutes.post("forumpost", postIDParam, "setstate", modStateParam, use: setForumPostModerationStatePostHandler)
		modPrivateRoutes.post("forum", forumIDParam, "setstate", modStateParam, use: setForumModerationStatePostHandler)
		modPrivateRoutes.post("fezpost", postIDParam, "setstate", modStateParam, use: setFezPostModerationStatePostHandler)
		modPrivateRoutes.post("lfg", fezIDParam, "setstate", modStateParam, use: setFezModerationStatePostHandler)
		modPrivateRoutes.post("userprofile", userIDParam, "setstate", modStateParam, use: setUserProfileModerationStatePostHandler)
		modPrivateRoutes.post("photostream", streamPhotoParam, "delete", use: modDeletePhotostreamPhoto)
		modPrivateRoutes.delete("photostream", streamPhotoParam, use: modDeletePhotostreamPhoto)

		modPrivateRoutes.post("forum", forumIDParam, "setcategory", categoryIDParam, use: setForumCategoryPostHandler)
		modPrivateRoutes.post("moderate", "user", userIDParam, "setaccesslevel", accessLevelParam, use: setUserAccessLevelPostHandler)
		modPrivateRoutes.post("moderate", "user", userIDParam, "tempquarantine", use: applyTempBanPostHandler)
		modPrivateRoutes.post("moderate", "user", userIDParam, "tempquarantine", "delete", use: removeTempBanPostHandler)
		modPrivateRoutes.post("microkaraoke", "song", mkSongIDParam, "approve", use: setMKSongApprovalState)
		modPrivateRoutes.post("microkaraoke", "snippet", mkSnippetIDParam, "delete", use: deleteMKSnippet)
		modPrivateRoutes.delete("microkaraoke", "snippet", mkSnippetIDParam, use: deleteMKSnippet)

		modPrivateRoutes.post("reports", reportIDParam, "handle", use: beginProcessingReportsPostHandler)
		modPrivateRoutes.post("reports", reportIDParam, "close", use: closeReportsPostHandler)
	}

	// GET /moderator
	// Shows the root moderator page, which just shows links to other pages.
	func moderatorRootPageHandler(_ req: Request) async throws -> View {
		struct ModeratorRootPageContext: Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Moderator Pages", tab: .moderator)
			}
		}
		let ctx = try ModeratorRootPageContext(req)
		return try await req.view.render("moderation/root", ctx)
	}

	/// `GET /archivedimage/ID`
	///
	/// Moderators only. Returns an image from the image archive (user images that have been replaced by subsequent edits).
	func archivedImageHandler(_ req: Request) async throws -> Response {
		guard let imageID = req.parameters.get(imageIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing image_id parameter.")
		}
		let apiResponse = try await apiQuery(req, endpoint: "/image/archive/\(imageID)")
		var body = Response.Body.empty
		if let apiResponseBody = apiResponse.body {
			body = Response.Body(buffer: apiResponseBody)
		}
		let response = Response(status: apiResponse.status, headers: apiResponse.headers, body: body)
		return response
	}

	/// `GET /reports`
	///
	/// Shows moderators a summary of user-submitted reports, grouped by the content that was reported.
	func reportsPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/mod/reports")
		let reports = try response.content.decode([ReportModerationData].self)
		let reportedContentArray = generateContentGroups(from: reports)
		let openReportContent = reportedContentArray.compactMap { $0.openCount > 0 ? $0 : nil }
		let ctx = try ReportsContext(req, reports: openReportContent)
		return try await req.view.render("moderation/reports", ctx)
	}

	/// `GET /reports/closed`
	///
	/// Shows moderators a summary of user-submitted reports, grouped by the content that was reported.
	func closedReportsPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/mod/reports")
		let reports = try response.content.decode([ReportModerationData].self)
		let reportedContentArray = generateContentGroups(from: reports)
		let closedReportContent = reportedContentArray.compactMap { $0.openCount > 0 ? nil : $0 }
		let ctx = try ReportsContext(req, reports: closedReportContent, isClosed: true)
		return try await req.view.render("moderation/reports", ctx)
	}

	/// `POST /reports/ID/handle`
	///
	/// Marks all reports reporting a specific piece of content as being handled by the current user. While a moderator is handling a report, any
	/// moderation actions taken get tied to the report being handled. Also, reports being handled are marked as such so other moderators can
	/// hopefully avoid duplicate work. Mods should close reports when they're done to complete the flow.
	func beginProcessingReportsPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let reportID = req.parameters.get(reportIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/reports/\(reportID)/handleall", method: .POST)
		return response.status
	}

	/// `POST /reports/ID/close`
	///
	/// Sets the state of all reports in a group to Closed. Although it takes an ID of one report, it finds all reports that refer to the same pirce
	/// of content, and closes all of them.
	func closeReportsPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let reportID = req.parameters.get(reportIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/reports/\(reportID)/closeall", method: .POST)
		return response.status
	}

	/// `GET /moderator/log`
	///
	/// Shows a page with a table of all moderator actions.
	func moderatorLogPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/mod/moderationlog")
		let logData = try response.content.decode(ModeratorActionLogResponseData.self)
		struct LogContext: Encodable {
			var trunk: TrunkContext
			var log: [ModeratorActionLogData]
			var paginator: PaginatorContext

			init(_ req: Request, responseData: ModeratorActionLogResponseData) throws {
				trunk = .init(req, title: "Moderator Action Log", tab: .moderator)
				self.log = responseData.actions
				self.paginator = PaginatorContext(
					start: responseData.paginator.start,
					total: responseData.paginator.total,
					limit: responseData.paginator.limit,
					urlForPage: { pageIndex in
						"/moderator/log?start=\(pageIndex * responseData.paginator.limit)&limit=\(responseData.paginator.limit)"
					}
				)
			}
		}
		let ctx = try LogContext(req, responseData: logData)
		return try await req.view.render("moderation/moderatorActionLog", ctx)
	}

	// `GET /moderator/seamail`
	func moderatorSeamailPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/joined?type=closed")
		let fezList = try response.content.decode(FezListData.self)
		// Re-sort fezzes so ones with new msgs are first. Keep most-recent-change sort within each group.
		var newMsgFezzes: [FezData] = []
		var noNewMsgFezzes: [FezData] = []
		fezList.fezzes.forEach {
			if let members = $0.members, members.postCount > members.readCount {
				newMsgFezzes.append($0)
			}
			else {
				noNewMsgFezzes.append($0)
			}
		}
		let allFezzes = newMsgFezzes + noNewMsgFezzes
		struct SeamailRootPageContext: Encodable {
			var trunk: TrunkContext
			var fezList: FezListData
			var fezzes: [FezData]
			var paginator: PaginatorContext

			init(_ req: Request, fezList: FezListData, fezzes: [FezData]) throws {
				trunk = .init(req, title: "Seamail", tab: .moderator)
				self.fezList = fezList
				self.fezzes = fezzes
				let limit = fezList.paginator.limit
				paginator = .init(fezList.paginator) { pageIndex in
					"/seamail?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try SeamailRootPageContext(req, fezList: fezList, fezzes: allFezzes)
		return try await req.view.render("moderation/moderatorSeamail", ctx)
	}

	/// `GET /moderator/guide`
	///
	///
	func moderatorGuidePageHandler(_ req: Request) async throws -> View {
		struct GuideContext: Encodable {
			var trunk: TrunkContext
			init(_ req: Request) throws {
				trunk = .init(req, title: "Moderator Guide", tab: .moderator)
			}
		}
		let ctx = try GuideContext(req)
		return try await req.view.render("moderation/guide", ctx)
	}

	///	`GET /moderate/twarrt/ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The twarrt that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	func moderateTwarrtContentPageHandler(_ req: Request) async throws -> View {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/twarrt/\(twarrtID)")
		let modData = try response.content.decode(TwarrtModerationData.self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: TwarrtModerationData
			var firstReport: ReportModerationData?
			var finalEditAuthor: UserHeader?

			init(_ req: Request, modData: TwarrtModerationData) throws {
				trunk = .init(req, title: "Reports", tab: .moderator)
				self.modData = modData
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				finalEditAuthor = modData.edits.last?.author
				if self.modData.edits.count > 1 {
					for index in (0...self.modData.edits.count - 2).reversed() {
						self.modData.edits[index + 1].author = self.modData.edits[index].author
						self.modData.edits[index + 1].author.username =
							"\(self.modData.edits[index + 1].author.username) edited to:"
					}
				}
				if self.modData.edits.count > 0 {
					self.modData.edits[0].author = modData.twarrt.author
					self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"

				}
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/twarrtView", ctx)
	}

	///	`POST /moderate/twarrt/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given twarrt. Moderation states include "locked" and "quarantined", as well as a few others.
	func setTwarrtModerationStatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/twarrt/\(twarrtID)/setstate/\(modState)", method: .POST)
		return response.status
	}

	/// `GET /moderate/forumpost/:post_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The post that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// *
	func moderateForumPostContentPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/forumpost/\(postID)")
		let modData: ForumPostModerationData = try response.content.decode(ForumPostModerationData.self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: ForumPostModerationData
			var firstReport: ReportModerationData?
			var finalEditAuthor: UserHeader?

			init(_ req: Request, modData: ForumPostModerationData) throws {
				trunk = .init(req, title: "Reports", tab: .moderator)
				self.modData = modData
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				finalEditAuthor = modData.edits.last?.author
				if self.modData.edits.count > 1 {
					for index in (0...self.modData.edits.count - 2).reversed() {
						self.modData.edits[index + 1].author = self.modData.edits[index].author
						self.modData.edits[index + 1].author.username =
							"\(self.modData.edits[index + 1].author.username) edited to:"
					}
				}
				if self.modData.edits.count > 0 {
					self.modData.edits[0].author = modData.forumPost.author
					self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"

				}
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/forumPostView", ctx)
	}

	///	`POST /moderate/forumpost/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given forum post. Moderation states include "locked" and "quarantined", as well as a few others.
	func setForumPostModerationStatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/forumpost/\(postID)/setstate/\(modState)", method: .POST)
		return response.status
	}

	/// `GET /moderate/forum/:forum_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The forum that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// *
	func moderateForumContentPageHandler(_ req: Request) async throws -> View {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let categoriesResponse = try await apiQuery(req, endpoint: "/forum/categories")
		let forumResponse = try await apiQuery(req, endpoint: "/mod/forum/\(forumID)")
		let modData = try forumResponse.content.decode(ForumModerationData.self)
		let categoryData = try categoriesResponse.content.decode([CategoryData].self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: ForumModerationData
			var firstReport: ReportModerationData?
			var finalEditAuthor: UserHeader?
			var finalEditPrevCategory: String?
			var currentCategory: String?
			var categories: [CategoryData]

			init(_ req: Request, modData: ForumModerationData, categories: [CategoryData]) throws {
				let categoryDict = categories.reduce(into: [:]) { $0[$1.categoryID] = $1 }
				trunk = .init(req, title: "Reports", tab: .moderator)
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
							self.modData.edits[index + 1].author.username =
								"\(self.modData.edits[index + 1].author.username) edited to:"
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
		return try await req.view.render("moderation/forumView", ctx)
	}

	///	`POST /moderate/forum/:forum_ID/move/:category_ID`
	///
	/// Moves a forum thread into a new category. Once moved, the thread will have the same restrictions on viewability as other threads in the destination category.
	/// This means we could make a 'forum dumpster' category that was mod-only and mods could move awful forum threads into it, and later review individual posts
	/// and hand out bans. The utility of this approach is: without this we don't have a way to get a forum out of circulation without deleting the whole forum.
	func setForumCategoryPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum ID parameter.")
		}
		guard let categoryID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing category ID parameter.")
		}
		let response = try await apiQuery(
			req,
			endpoint: "/mod/forum/\(forumID)/setcategory/\(categoryID)",
			method: .POST
		)
		return response.status
	}

	///	`POST /moderate/forum/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given forum. Moderation states include "locked" and "quarantined", as well as a few others.
	func setForumModerationStatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/forum/\(forumID)/setstate/\(modState)", method: .POST)
		return response.status
	}

	/// `GET /moderate/lfg/:fez_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The Fez that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// *
	func moderateFezContentPageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/fez/\(fezID)")
		let modData = try response.content.decode(FezModerationData.self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: FezModerationData
			var firstReport: ReportModerationData?
			var finalEditAuthor: UserHeader?

			init(_ req: Request, modData: FezModerationData) throws {
				trunk = .init(req, title: "LFG Moderation", tab: .moderator)
				self.modData = modData
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				finalEditAuthor = modData.edits.last?.author
				if self.modData.edits.count > 1 {
					for index in (0...self.modData.edits.count - 2).reversed() {
						self.modData.edits[index + 1].author = self.modData.edits[index].author
						self.modData.edits[index + 1].author.username =
							"\(self.modData.edits[index + 1].author.username) edited to:"
					}
				}
				if self.modData.edits.count > 0 {
					self.modData.edits[0].author = modData.fez.owner
					self.modData.edits[0].author.username = "\(self.modData.edits[0].author.username) initially wrote:"
				}
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/fezView", ctx)
	}

	///	`POST /moderate/lfg/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given fez. Moderation states include "locked" and "quarantined", as well as a few others.
	func setFezModerationStatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/fez/\(fezID)/setstate/\(modState)", method: .POST)
		return response.status
	}

	/// `GET /moderate/fezpost/:fezpost_ID`
	///
	/// This shows a view that focuses on the *content* that was reported, showing:
	/// * The Fez Post that was reported
	/// * All reports made against this content
	/// * All previous versions of this content
	/// * (hopefully) Mod actions taken against this content already
	/// *
	func moderateFezPostContentPageHandler(_ req: Request) async throws -> View {
		guard let fezPostID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/fezpost/\(fezPostID)")
		let modData = try response.content.decode(FezPostModerationData.self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: FezPostModerationData
			var firstReport: ReportModerationData?
			var finalEditAuthor: UserHeader?
			var postModUrl: String
			var postContentType: String // @TODO enum?

			init(_ req: Request, modData: FezPostModerationData) throws {
				self.modData = modData
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				switch modData.fezType {
					case .open, .closed:
						self.postModUrl = "/seamail/\(modData.fezID)"
						self.postContentType = "Seamail"
					default:
						self.postModUrl = "/lfg/\(modData.fezID)"
						self.postContentType = "LFG"
				}

				trunk = .init(req, title: "\(self.postContentType) Post Moderation", tab: .moderator)
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/fezPostView", ctx)
	}

	///	`POST /moderate/fezpost/:post_ID/setstate/STRING`
	///
	/// Sets the moderation state of the given fez. Moderation states include "locked" and "quarantined", as well as a few others.
	func setFezPostModerationStatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/fezpost/\(postID)/setstate/\(modState)", method: .POST)
		return response.status
	}

	/// `GET /moderate/microkaraoke`
	///
	/// This shows a view that shows the MicroKaraoke songs that are:
	/// - Completed/Approved: Approved by mods, ready for viewing by all users.
	/// - Completed/Not Approved: Not yet approved, but all necessary video clips have been uploaded
	/// - Not Completed: Songs that do not yet have all their video clips uploaded
	func getMicroKaraokeSongsPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/mod/microkaraoke/songlist")
		let modData = try response.content.decode([MicroKaraokeCompletedSong].self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: [MicroKaraokeCompletedSong]

			init(_ req: Request, modData: [MicroKaraokeCompletedSong]) throws {
				trunk = .init(req, title: "Micro Karaoke Moderation", tab: .moderator)
				self.modData = modData
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/mkSongsView", ctx)
	}
	
	/// `GET /moderate/microkaraoke/song/:song_id`
	///
	/// For a specific Micro Karaoke song, shows a list of each video clip that makes up the song, along with the user that recorded that clip and a 'Reject' button
	/// for moderation purposes.
	func moderateMicroKaraokeSongPageHandler(_ req: Request) async throws -> View {
		guard let songID = req.parameters.get(mkSongIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing songID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/microkaraoke/song/\(songID)")
		let songInfo = try response.content.decode(MicroKaraokeCompletedSong.self)
		let response2 = try await apiQuery(req, endpoint: "/mod/microkaraoke/snippets/\(songID)")
		let modData = try response2.content.decode([MicroKaraokeSnippetModeration].self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var songInfo: MicroKaraokeCompletedSong
			var modData: [MicroKaraokeSnippetModeration]
			var numSlotsUploaded: Int
			var numSlotsOffered: Int			// Only includes non-expired offers, even through they might be accepted late.
			var numFillerSlots: Int				// Most songs have a few filler sections with no vocals.

			init(_ req: Request, modData: [MicroKaraokeSnippetModeration], songInfo: MicroKaraokeCompletedSong) throws {
				trunk = .init(req, title: "Micro Karaoke Moderation", tab: .moderator)
				self.songInfo = songInfo
				self.modData = modData
				
				numFillerSlots = 0
				numSlotsOffered = 0
				numSlotsUploaded = 0
				for clip in modData {
					if clip.user.username == "MicroKaraoke" {
						numFillerSlots += 1
					}
					else if clip.videoURL == nil {
						numSlotsOffered += 1
					}
					else {
						numSlotsUploaded += 1
					}
				}
			}
		}
		let ctx = try ReportContext(req, modData: modData, songInfo: songInfo)
		return try await req.view.render("moderation/mkSnippetView", ctx)
	}

	///	`POST /moderate/microkaraoke/:song_ID/approve`
	///
	/// Approves the given song for publish. Notifies all contributors that their song is ready for viewing.
	func setMKSongApprovalState(_ req: Request) async throws -> HTTPStatus {
		guard let songID = req.parameters.get(mkSongIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing songID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/microkaraoke/approve/\(songID)", method: .POST)
		return response.status
	}
	
	///	`POST /microkaraoke/snippet/:snippet_ID/delete`
	///
	/// Approves the given song for publish. Notifies all contributors that their song is ready for viewing.
	func deleteMKSnippet(_ req: Request) async throws -> HTTPStatus {
		guard let snippetID = req.parameters.get(mkSnippetIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing snippetID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/microkaraoke/snippet/\(snippetID)/delete", method: .POST)
		return response.status
	}
		
	/// `GET /moderate/photostream/ID`
	///
	/// For linking individual photostream photos from user reports.
	func moderatePhotostreamPhotoPageHandler(_ req: Request) async throws -> View {
		guard let photostreamID = req.parameters.get(streamPhotoParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/photostream/\(photostreamID)")
		let modData = try response.content.decode(PhotostreamModerationData.self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: PhotostreamModerationData
			var firstReport: ReportModerationData?

			init(_ req: Request, modData: PhotostreamModerationData) throws {
				self.modData = modData
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				trunk = .init(req, title: "Photostream Photo Moderation", tab: .moderator)
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/streamPhoto", ctx)
	}

	///	`POST /moderate/photostream/:photo_ID/delete`
	///	`DELETE /moderate/photostream/:photo_ID`
	///
	/// Deletes the given photo from the photostream.
	func modDeletePhotostreamPhoto(_ req: Request) async throws -> HTTPStatus {
		guard let photoID = req.parameters.get(streamPhotoParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing photoID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/photostream/\(photoID)/delete", method: .POST)
		return response.status
	}

	/// `GET /moderate/userprofile/ID`
	///
	/// Info from user's profile. Previous profile versions, reports against the user's profile fields or avatar image.
	func moderateUserProfileContentPageHandler(_ req: Request) async throws -> View {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/profile/\(userID)")
		let modData = try response.content.decode(ProfileModerationData.self)
		struct UserModContext: Encodable {
			var trunk: TrunkContext
			var modData: ProfileModerationData
			var firstReport: ReportModerationData?
			var finalEditAuthor: UserHeader?

			init(_ req: Request, modData: ProfileModerationData) throws {
				trunk = .init(req, title: "User Profile Moderation", tab: .moderator)
				self.modData = modData
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
				finalEditAuthor = modData.edits.last?.author
				if self.modData.edits.count > 1 {
					for index in (0...self.modData.edits.count - 2).reversed() {
						self.modData.edits[index + 1].author = self.modData.edits[index].author
						self.modData.edits[index + 1].author.username =
							"\(self.modData.edits[index + 1].author.username) edited to:"
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
		return try await req.view.render("moderation/profileView", ctx)
	}

	///	`POST /moderate/userprofile/ID/setstate/STRING`
	///
	/// Sets the moderation state of the given user's profile. ID is a userID UUID.. Moderation states include "locked" and "quarantined", as well as a few others.
	/// Again: Setting the state to "locked" prevents the user from modifying their profile and avatar, but doesn't otherwise constrain them.
	/// Similarly, quarantine state prevents others from seeing the avatar and profile field text, but doesn't prevent the user from posting content.
	func setUserProfileModerationStatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		guard let modState = req.parameters.get(modStateParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/profile/\(userID)/setstate/\(modState)", method: .POST)
		return response.status
	}

	/// `GET /moderate/user/ID`
	///
	/// Shows the User Moderation page, which has the user's accessLevel controls, temp banning, and a list of all reports
	/// filed against any of this user's content.
	func moderateUserContentPageHandler(_ req: Request) async throws -> View {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/user/\(userID)")
		let modData = try response.content.decode(UserModerationData.self)
		struct UserModContext: Encodable {
			var trunk: TrunkContext
			var modData: UserModerationData
			var accessLevelString: String
			var reportGroups: [ReportContentGroup]

			init(_ req: Request, modData: UserModerationData) throws {
				trunk = .init(req, title: "User Moderation", tab: .moderator)
				self.modData = modData
				accessLevelString = modData.accessLevel.visibleName()
				reportGroups = generateContentGroups(from: modData.reports)
			}
		}
		let ctx = try UserModContext(req, modData: modData)
		return try await req.view.render("moderation/userView", ctx)
	}

	///	`POST /moderate/user/ID/setaccesslevel/STRING`
	///
	/// Sets the moderation state of the given user's profile. ID is a userID UUID.. Moderation states include "locked" and "quarantined", as well as a few others.
	/// Again: Setting the state to "locked" prevents the user from modifying their profile and avatar, but doesn't otherwise constrain them.
	/// Similarly, quarantine state prevents others from seeing the avatar and profile field text, but doesn't prevent the user from posting content.
	func setUserAccessLevelPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing userID parameter.")
		}
		guard let accessLevel = req.parameters.get(accessLevelParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing access level parameter.")
		}
		let response = try await apiQuery(
			req,
			endpoint: "/mod/user/\(userID)/setaccesslevel/\(accessLevel)",
			method: .POST
		)
		return response.status
	}

	///	`POST /moderate/user/ID/tempquarantine`
	///
	/// Applies a temporary quarantine to the user given by ID. While quarantined, the user may not create or edit content,
	/// but can still log in and read others' content. They can still talk in private Seamail chats. They cannot edit their profile or change their avatar image.
	/// Temp quarantines effectively change the user's accessLevel to `.quarantined` for the duration, after which the user's accessLevel reverts
	/// to what it was previously.
	func applyTempBanPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing userID parameter.")
		}
		struct TempBanFormData: Content {
			var banlength: Int
		}
		let postStruct = try req.content.decode(TempBanFormData.self)
		let response = try await apiQuery(
			req,
			endpoint: "/mod/user/\(userID)/tempquarantine/\(postStruct.banlength)",
			method: .POST
		)
		return response.status
	}

	///	`POST /moderate/user/ID/tempquarantine/delete`
	///
	/// Applies a temporary quarantine to the user given by ID. While quarantined, the user may not create or edit content,
	/// but can still log in and read others' content. They can still talk in private Seamail chats. They cannot edit their profile or change their avatar image.
	/// Temp quarantines effectively change the user's accessLevel to `.quarantined` for the duration, after which the user's accessLevel reverts
	/// to what it was previously.
	func removeTempBanPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing userID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/user/\(userID)/tempquarantine/0", method: .POST)
		return response.status
	}

	// MARK: PersonalEvent Moderation

	/// `GET /moderate/personalevent/:eventID`
	///
	/// Shows the moderate page for PersonalEvents.
	func moderatePersonalEventPageHandler(_ req: Request) async throws -> View {
		guard let eventID = req.parameters.get(personalEventIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing personalevent_id parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/mod/personalevent/\(eventID)")
		let modData = try response.content.decode(PersonalEventModerationData.self)
		struct ReportContext: Encodable {
			var trunk: TrunkContext
			var modData: PersonalEventModerationData
			// Needed for Events/personalEvent templating
			var event: PersonalEventData
			var firstReport: ReportModerationData?

			init(_ req: Request, modData: PersonalEventModerationData) throws {
				self.modData = modData
				trunk = .init(req, title: "Personal Event Moderation", tab: .moderator)
				self.event = modData.personalEvent
				firstReport = modData.reports.count > 0 ? modData.reports[0] : nil
			}
		}
		let ctx = try ReportContext(req, modData: modData)
		return try await req.view.render("moderation/personalEvent", ctx)
	}

}

// MARK: - Utilities

// Groups reports that are reporting on the same thing; returns `ReportContentGroup` array with one
// entry per reported content
func generateContentGroups(from reports: [ReportModerationData]) -> [ReportContentGroup] {
	var reportedContentArray = [ReportContentGroup]()
	for report in reports {
		if let index = reportedContentArray.firstIndex(where: {
			report.reportedID == $0.reportedID && report.type == $0.reportType
		}) {
			var content = reportedContentArray[index]
			content.openCount += report.isClosed ? 0 : 1
			if report.handledBy != nil {
				content.handledBy = report.handledBy
			}
			if content.firstReport.creationTime > report.creationTime {
				content.firstReport = report
			}
			content.reports.append(report)
			reportedContentArray[index] = content
			continue
		}

		var contentURL: String
		switch report.type {
		case .twarrt: contentURL = "/moderate/twarrt/\(report.reportedID)"
		case .forumPost: contentURL = "/moderate/forumpost/\(report.reportedID)"
		case .forum: contentURL = "/moderate/forum/\(report.reportedID)"
		case .fez: contentURL = "/moderate/lfg/\(report.reportedID)"
		case .fezPost: contentURL = "/moderate/fezpost/\(report.reportedID)"
		case .userProfile: contentURL = "/moderate/userprofile/\(report.reportedID)"
		case .mkSong: contentURL = "/moderate/microkaraoke/song/\(report.reportedID)"
		case .mkSongSnippet: contentURL = "/moderate/microkaraoke/song/\(report.reportedID)"	// Individual snippets aren't actually reportable yet.
		case .streamPhoto: contentURL = "/moderate/photostream/\(report.reportedID)"
		case .personalEvent: contentURL = "/moderate/personalevent/\(report.reportedID)"
		}
		var newGroup = ReportContentGroup(
			reportType: report.type,
			reportedID: report.reportedID,
			reportedUser: report.reportedUser,
			firstReport: report,
			openCount: 0,
			handledBy: report.handledBy,
			contentURL: contentURL,
			reports: [report]
		)
		newGroup.openCount += report.isClosed ? 0 : 1
		reportedContentArray.append(newGroup)
	}
	return reportedContentArray
}
