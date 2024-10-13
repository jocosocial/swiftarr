import FluentSQL
import LeafKit
import Vapor
import RegexBuilder

struct PerformersListContext: Encodable {
	var trunk: TrunkContext
	var performers: PerformerResponseData
	var searchText: String
	var paginator: PaginatorContext
	var officialPerformers: Bool
	var titleString: String

	init(_ req: Request, performers: PerformerResponseData, official: Bool) throws {
		trunk = .init(req, title: "Performers", tab: .home)
		self.performers = performers
		searchText = req.query[String.self, at: "search"] ?? ""
		let limit = performers.paginator.limit
		paginator = .init(performers.paginator) { pageIndex in
			"/boardgames?start=\(pageIndex * limit)&limit=\(limit)"
		}
		self.officialPerformers = official
		self.titleString = official ? "JoCo Performers" : "Shadow Cruise Event Organizers"
	}
}

struct PerformerContext: Encodable {
	var trunk: TrunkContext
	var performer: PerformerData

	init(_ req: Request, performer: PerformerData) throws {
		trunk = .init(req, title: "Performer", tab: .home)
		self.performer = performer
	}
}

// Form data from the Add/Update Event Organizer and Add/Update Performer form
fileprivate struct AddPerformerFormContent: Codable {
	var performerID: UUID?		// non-nil if editing an existing performer
	var eventUID: String?			// non-nil if we're linking this performer to this event
	var name: String
	var pronouns: String?
	var photoURL: String?
	var photo: Data?
	var serverPhoto: String?
	var org: String?
	var title: String?
	var bio: String?
	var website: String?
	var facebookURL: String?
	var xURL: String?
	var instagramURL: String?
	var youtubeURL: String?
	var yearsAttended: String?
	var isOfficialPerformer: Bool?
}


struct SitePerformerController: SiteControllerUtils {
	func registerRoutes(_ app: Application) throws {
	
		let globalRoutes = getOpenRoutes(app, feature: .performers)
		globalRoutes.get("performers", use: officialPerformersPageHandler).setUsedForPreregistration()
		globalRoutes.get("performer", performerIDParam, use: performerPageHandler).setUsedForPreregistration()
		globalRoutes.get("performers", "shadow", use: shadowPerformersPageHandler).setUsedForPreregistration()
		
		let privateRoutes = getPrivateRoutes(app, feature: .performers)
		privateRoutes.get("performer", "shadow", "addtoevent", eventIDParam, use: addEventOrganizer).setUsedForPreregistration()
		privateRoutes.post("performer", "shadow", "add", eventIDParam, use: postAddEventOrganizer).setUsedForPreregistration()
		
		let ttRoutes = getPrivateRoutes(app, feature: .performers, minAccess: .twitarrteam)
		ttRoutes.get("admin", "performer", "root", use: getPerformersRoot)
		ttRoutes.get("admin", "performer", "add", use: upsertPerformer)
		ttRoutes.post("admin", "performer", "add", use: postUpsertPerformer)
		
		ttRoutes.get("admin", "performer", "link", use: linkPerformersPage)
		ttRoutes.post("admin", "performer", "link", "upload", use: postLinkPerformersUpload)
		ttRoutes.get("admin", "performer", "link", "verify", use: showLinkPerformersVerifyResults)
		ttRoutes.post("admin", "performer", "link", "apply", use: postLinkPerformersApply)
	}
	
	/// `GET /performers`
	///
	/// Returns a list of Official Performers matching the query. Pageable.
	///
	/// Query Parameters:
	/// - search=STRING		Filter only performers whose title that match the given string.
	/// - start=INT
	/// - limit=INT
	func officialPerformersPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/performer/official")
		let performers = try response.content.decode(PerformerResponseData.self)
		let context = try PerformersListContext(req, performers: performers, official: true)
		return try await req.view.render("Performers/list", context)
	}
	
	/// `GET /performers/shadow`
	///
	/// Returns a list of Shadow Event Performers matching the query. Pageable. This route MAY OR MAY NOT end up being viewable by all users,
	/// but WILL need to be available to mods to access for moderation purposes.
	///
	/// Query Parameters:
	/// - search=STRING		Filter only performers whose title that match the given string.
	/// - start=INT
	/// - limit=INT
	func shadowPerformersPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/performer/shadow")
		let performers = try response.content.decode(PerformerResponseData.self)
		let context = try PerformersListContext(req, performers: performers, official: false)
		return try await req.view.render("Performers/list", context)
	}
	
	/// `GET /performer/:performer_ID`
	///
	/// Shows the Bio page for the indicated performer.
	func performerPageHandler(_ req: Request) async throws -> View {
		guard let performerID = req.parameters.get(performerIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Performer is missing.")
		}
		let response = try await apiQuery(req, endpoint: "/performer/\(performerID)")
		let performer = try response.content.decode(PerformerData.self)
		let context = try PerformerContext(req, performer: performer)
		return try await req.view.render("Performers/bio", context)
	}
	
	// `GET /performer/shadow/addtoevent/:event_id`
	//
	// Shows a form that lets a user fill in a Performer profle for themselves, and marks themselves as the organizer/performer/speaker
	// for the given event.
	func addEventOrganizer(_ req: Request) async throws -> View {
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Missing event ID parameter.")
		}
		let event = try await apiQuery(req, endpoint: "/events/\(eventID)").content.decode(EventData.self)
		if event.eventType != "Shadow Event" {
			throw Abort(.badRequest, reason: "The referenced event is not a Shadow Event; you can't use this form to modify it.")
		}
		let performer = try await apiQuery(req, endpoint: "/performer/self").content.decode(PerformerData.self)
		struct AddOrganizerPageContext: Encodable {
			var trunk: TrunkContext
			var performer: PerformerData
			var event: EventData
			var formAction: String
			var deleteAction: String?
			var alreadyAttached: Bool		// TRUE if this performer is already attached to this event
			
			init(_ req: Request, performer: PerformerData, event: EventData) throws {
				trunk = .init(req, title: "Add/Modify Event Organizer", tab: .events)
				self.performer = performer
				self.event = event
				self.formAction = "/performer/shadow/add/\(event.eventID)"
				if let _ = performer.header.id {
					self.deleteAction = "/performer/self/delete"
					alreadyAttached = performer.events.contains { $0.eventID == event.eventID }
				}
				else {
					alreadyAttached = false
				}
			}
		}
		let ctx = try AddOrganizerPageContext(req, performer: performer, event: event)
		return try await req.view.render("Performers/addOrganizer", ctx)
	}
	
	// `POST /performer/shadow/add/:event_id`
	//
	func postAddEventOrganizer(_ req: Request) async throws -> HTTPStatus {
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Missing event ID parameter.")
		}
		let postStruct = try req.content.decode(AddPerformerFormContent.self)
		var photoData: Data?
		var serverPhotoName: String? = nil
		if let data = postStruct.photo, !data.isEmpty {
			photoData = data
		}
		else if let photoURL = postStruct.photoURL, !photoURL.isEmpty {
			// Some browser safety configurations (Chrome's defaults?) won't let JS get image data from an image dropped from another
			// server, but will let JS get the URL of the drag and drop image. Since this is an issue that only affects browser clients
			// it's probably better to handle this in the front end.
			let response = try await req.client.send(.GET, to: URI(string: photoURL))
			if let body = response.body {
				photoData = Data(buffer: body)
			}
		} else {
			serverPhotoName = postStruct.serverPhoto
		}
		var uploadData = PerformerUploadData(form: postStruct, photo:  ImageUploadData(filename: serverPhotoName, image: photoData))
		uploadData.isOfficialPerformer = false
		try await apiQuery(req, endpoint: "/performer/forevent/\(eventID)", method: .POST, encodeContent: uploadData)
		return .ok
	}
	
	// MARK:  TT Routes
	
	// `GET /admin/performer/root`
	//
	func getPerformersRoot(_ req: Request) async throws -> View {
		struct PerformerPageContext: Encodable {
			var trunk: TrunkContext
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "Performers Admin Page", tab: .events)
			}
		}
		let ctx = try PerformerPageContext(req)
		return try await req.view.render("Performers/adminRoot", ctx)
	}
	
	
	// `GET /admin/performer/add`
	//
	// Adds an official performer to the performer list, or edits an existing official or shadow performer.
	// Only TwitarrTeam and above can access.
	// - Parameter performer: UUID. In URL Query. Set if this is an edit of an existing performer.
	func upsertPerformer(_ req: Request) async throws -> View {
		var performer: PerformerData?
		if let performerID = req.query[UUID.self, at: "performer"] {
			performer = try await apiQuery(req, endpoint: "/performer/\(performerID)").content.decode(PerformerData.self)
		}
		else {
			performer = PerformerData()
			performer?.header.isOfficialPerformer = true
		}
		struct AddPerformerPageContext: Encodable {
			var trunk: TrunkContext
			var performer: PerformerData?
			var formAction: String
			var deleteAction: String?
			var attendedYears: [String]
			
			init(_ req: Request, performer: PerformerData?) throws {
				trunk = .init(req, title: "Add/Modify Official Performer Bio", tab: .events)
				self.performer = performer
				self.formAction = "/admin/performer/add"
				if let _ = performer?.header.id {
					self.deleteAction = "/admin/performer/delete"
				}
				let currentYear = Settings.shared.cruiseStartDateComponents.year ?? 2024
				var years = performer?.yearsAttended ?? [currentYear]
				if !years.contains(currentYear) {
					years.append(currentYear)
				}
				attendedYears = years.map { String($0) }
			}
		}
		let ctx = try AddPerformerPageContext(req, performer: performer)
		return try await req.view.render("Performers/addPerformer", ctx)
	}
	
	// `POST /admin/performer/add`
	//
	// Takes the HTML form for adding/updating a performer, sends it to the API layer.
	// Only TwitarrTeam and above can access.
	func postUpsertPerformer(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(AddPerformerFormContent.self)
		var photoData: Data?
		var serverPhotoName: String? = nil
		if let data = postStruct.photo, !data.isEmpty {
			photoData = data
		}
		else if let photoURL = postStruct.photoURL, !photoURL.isEmpty {
			// Some browser safety configurations (Chrome's defaults?) won't let JS get image data from an image dropped from another
			// server, but will let JS get the URL of the drag and drop image. Since this is an issue that only affects browser clients
			// it's probably better to handle this in the front end.
			let response = try await req.client.send(.GET, to: URI(string: photoURL))
			if let body = response.body {
				photoData = Data(buffer: body)
			}
		} else {
			serverPhotoName = postStruct.serverPhoto
		}
		let uploadData = PerformerUploadData(form: postStruct, photo:  ImageUploadData(filename: serverPhotoName, image: photoData))
		try await apiQuery(req, endpoint: "/admin/performer/upsert", method: .POST, encodeContent: uploadData)
		return .ok
	}

	// `GET /admin/performer/link`
	//
	// Starts the flow for uploading and parsing an Excel spreadsheet that contains info on which performers are playing at which
	// events. This page has the upload form.
	func linkPerformersPage(_ req: Request) async throws -> View {
		struct LinkPerformersPageContext: Encodable {
			var trunk: TrunkContext
			var formAction: String
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "Link Performers To Events", tab: .events)
				self.formAction = "/admin/performer/link/upload"
			}
		}
		let ctx = try LinkPerformersPageContext(req)
		return try await req.view.render("Performers/bulkLink", ctx)
	}

	// `POST /admin/performer/link/upload`
	//
	// Takes a file upload containing an Excel spreadsheet.
	func postLinkPerformersUpload(_ req: Request) async throws -> HTTPStatus {
		struct ExcelFileUploadData: Content {
			var performerlinks: Data
		}
		let spreadsheet = try req.content.decode(ExcelFileUploadData.self)		
		try await apiQuery(req, endpoint: "/admin/performer/link/upload", method: .POST, encodeContent: spreadsheet.performerlinks)
		return .ok
	}
	
	// GET /admin/performer/link/verify
	//
	// Displays a page showing the schedule changes that will happen when the (saved) uploaded schedule is applied.
	// We diff the existing schedule with the new update, and display the adds, deletes, and modified events for review.
	// This page also has a form where the user can approve the changes to apply them to the db.
	func showLinkPerformersVerifyResults(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/performer/link/verify")
		let validationData = try response.content.decode(EventPerformerValidationData.self)

		struct PerformerLinkValidationContext: Encodable {
			var trunk: TrunkContext
			var diff: EventPerformerValidationData

			init(_ req: Request, validationData: EventPerformerValidationData) throws {
				trunk = .init(req, title: "Verify Schedule Changes", tab: .admin)
				self.diff = validationData
			}
		}
		let ctx = try PerformerLinkValidationContext(req, validationData: validationData)
		return try await req.view.render("Performers/bulkLinkVerify", ctx)
	}


	// POST /admin/performer/link/apply
	//
	// Applies the performer/event link changes.
	func postLinkPerformersApply(_ req: Request) async throws -> HTTPStatus {
		try await apiQuery(req, endpoint: "/admin/performer/link/apply", method: .POST)
		return .ok
	}
}

// Used to create a PerformerUploadData from the web form. Used in a couple of places.
extension PerformerUploadData {
	fileprivate init(form: AddPerformerFormContent, photo: ImageUploadData) {
		performerID = form.performerID
		if let eventUID = form.eventUID {
			eventUIDs = [eventUID]
		}
		else {
			eventUIDs = []
		}
		name = form.name
		pronouns = form.pronouns
		bio = form.bio
		self.photo = photo
		organization = form.org
		title = form.title
		website = form.website
		facebookURL = form.facebookURL
		xURL = form.xURL
		instagramURL = form.instagramURL
		youtubeURL = form.youtubeURL
		isOfficialPerformer = form.isOfficialPerformer ?? true
		yearsAttended = form.yearsAttended?.matches(of: #/20\d\d/#).compactMap { Int($0.output) }.sorted() ?? []
	}
}
