import Vapor
import Crypto
import FluentSQL

struct SiteAdminController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("admin")
		privateRoutes.get("announcements", use: announcementsAdminPageHandler)
		privateRoutes.get("announcement", "create", use: announcementCreatePageHandler)
		privateRoutes.post("announcement", "create", use: announcementCreatePostHandler)
		privateRoutes.get("announcement", announcementIDParam, "edit", use: announcementEditPageHandler)
		privateRoutes.post("announcement", announcementIDParam, "edit", use: announcementEditPostHandler)
		privateRoutes.post("announcement", announcementIDParam, "delete", use: announcementDeletePostHandler)
	}
	
	
// MARK: - Admin Pages

	// This exists because we can't eval `displayUntil < Date()` inside Leaf.
	struct AnnouncementViewData: Content {
		var id: Int
		var author: UserHeader
		var text: String
		var updatedAt: Date
		var displayUntil: Date
		var isDeleted: Bool
		var isExpired: Bool
		
		init(from: AnnouncementData) {
			id = from.id
			author = from.author
			text = from.text
			updatedAt = from.updatedAt
			displayUntil = from.displayUntil
			isDeleted = from.isDeleted
			isExpired = from.displayUntil < Date()
		}
	}

	// GET /admin/announcements
	// Shows a list of all existing announcements
	func announcementsAdminPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/notification/announcements?inactives=true").throwingFlatMap { response in
 			let announcements = try response.content.decode([AnnouncementData].self)
 			let announcementViews = announcements.map { AnnouncementViewData(from: $0) }
			struct AnnouncementPageContext : Encodable {
				var trunk: TrunkContext
				var announcements: [AnnouncementViewData]
				
				init(_ req: Request, announcements: [AnnouncementViewData]) throws {
					trunk = .init(req, title: "Announcements", tab: .none)
					self.announcements = announcements
				}
			}
			let ctx = try AnnouncementPageContext(req, announcements: announcementViews)
			return req.view.render("admin/announcements", ctx)
		}
	}
	
	// GET /admin/announcement/create
	func announcementCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct AnnouncementEditContext : Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext
			var timeZoneName: String

			init(_ req: Request) throws {
				trunk = .init(req, title: "Create Announcement", tab: .none)
				self.post = .init(forType: .announcement)
				timeZoneName = TimeZone.autoupdatingCurrent.abbreviation() ?? "EST"
			}
		}
		let ctx = try AnnouncementEditContext(req)
		return req.view.render("admin/announcementEdit", ctx)
	}
	
	// POST /admin/announcement/create
	func announcementCreatePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let text = postStruct.postText, let displayUntil = postStruct.displayUntil else {
			throw Abort(.badRequest, reason: "Input form is missing members.")
		}
		guard let displayUntilDate = dateFromW3DatetimeString(displayUntil) else {
			throw Abort(.badRequest, reason: "Display Until date is misformatted.")
		}
		let postContent = AnnouncementCreateData(text: text, displayUntil: displayUntilDate)
		return apiQuery(req, endpoint: "/notification/announcement/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
	}
	
	// GET /admin/announcement/ID/edit
	func announcementEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing announcement_id parameter.")
		}
		return apiQuery(req, endpoint: "/notification/announcement/\(announcementID)").throwingFlatMap { response in
 			let announcementData = try response.content.decode(AnnouncementData.self)

			struct AnnouncementEditContext : Encodable {
				var trunk: TrunkContext
				var post: MessagePostContext
				var timeZoneName: String

				init(_ req: Request, data: AnnouncementData) throws {
					trunk = .init(req, title: "Edit Announcement", tab: .none)
					self.post = .init(forType: .announcementEdit(data))
					timeZoneName = TimeZone.autoupdatingCurrent.abbreviation() ?? "EST"
				}
			}
			let ctx = try AnnouncementEditContext(req, data: announcementData)
			return req.view.render("admin/announcementEdit", ctx)
		}
	}
	
	// POST /admin/announcement/ID/edit
	func announcementEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing announcement_id parameter.")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let text = postStruct.postText, let displayUntil = postStruct.displayUntil else {
			throw Abort(.badRequest, reason: "Input form is missing members.")
		}
		guard let displayUntilDate = dateFromW3DatetimeString(displayUntil) else {
			throw Abort(.badRequest, reason: "Display Until date is misformatted.")
		}
		let postContent = AnnouncementCreateData(text: text, displayUntil: displayUntilDate)
		return apiQuery(req, endpoint: "/notification/announcement/\(announcementID)/edit", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
	}
	
	// POST /admin/announcement/ID/delete
	//
	// Deletes an announcement.
	func announcementDeletePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/notification/announcement/\(announcementID)", method: .DELETE).map { response in
			return response.status
		}
	}
}

