import FluentSQL
import LeafKit
import Vapor
import RegexBuilder
import SwiftSoup

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
		privateRoutes.post("performer", "self", "delete", use: selfPerformerDeleteHandler).setUsedForPreregistration()

		let ttRoutes = getPrivateRoutes(app, feature: .performers, minAccess: .twitarrteam)
		ttRoutes.get("admin", "performer", "root", use: getPerformersRoot)
		ttRoutes.get("admin", "performer", "add", use: upsertPerformer)
		ttRoutes.post("admin", "performer", "add", use: postUpsertPerformer)
		ttRoutes.post("admin", "performer", performerIDParam, "delete", use: performerDeleteHandler)
		
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
		if !["Shadow Event", "Workshop"].contains(event.eventType) {
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
		let uploadData = PerformerUploadData(form: postStruct, photo:  ImageUploadData(filename: serverPhotoName, image: photoData), 
				overrideIsOfficial: false)
		try await apiQuery(req, endpoint: "/performer/forevent/\(eventID)", method: .POST, encodeContent: uploadData)
		return .ok
	}

	// `POST /performer/self/delete`
	//
	func selfPerformerDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let response = try await apiQuery(req, endpoint: "/performer/self", method: .DELETE)
		return response.status
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
	// - Parameter performerurl: String. In URL Query. Set if the form should be filled in with data from jococruise.com.
	func upsertPerformer(_ req: Request) async throws -> View {
		var performer: PerformerData?
		var performerImageURL: String?
		if let performerID = req.query[UUID.self, at: "performer"] {
			performer = try await apiQuery(req, endpoint: "/performer/\(performerID)").content.decode(PerformerData.self)
		}
		else if let performerURL = req.query[String.self, at: "performerurl"] {
			performer = try await buildPerformerFromURL(performerURL, on: req)
			performerImageURL = performer?.header.photo
			performer?.header.photo = nil
			performer?.header.isOfficialPerformer = true
		}
		else {
			performer = PerformerData()
			performer?.header.isOfficialPerformer = true
		}
		struct AddPerformerPageContext: Encodable {
			var trunk: TrunkContext
			var performer: PerformerData?
			var performerImageURL: String?			// For 3rd party images that should appear on load
			var formAction: String
			var deleteAction: String?
			var attendedYears: [String]
			
			init(_ req: Request, performer: PerformerData?, image: String?) throws {
				trunk = .init(req, title: "Add/Modify Official Performer Bio", tab: .events)
				self.performer = performer
				self.performerImageURL = image
				self.formAction = "/admin/performer/add"
				if let performerID = performer?.header.id {
					self.deleteAction = "/admin/performer/\(performerID)/delete"
				}
				let currentYear = Settings.shared.cruiseStartDateComponents.year ?? 2025
				var years = performer?.yearsAttended ?? [currentYear]
				if !years.contains(currentYear) {
					years.append(currentYear)
				}
				attendedYears = years.map { String($0) }
			}
		}
		let ctx = try AddPerformerPageContext(req, performer: performer, image: performerImageURL)
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

	// `POST /performer/:performer_ID/delete`
	//
	func performerDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let performerID = req.parameters.get(performerIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Performer is missing.")
		}
		let response = try await apiQuery(req, endpoint: "/admin/performer/\(performerID)", method: .DELETE)
		return response.status
	}
}

extension SitePerformerController {
	// Scrapes the HTML found at the given url, builds a PerformerData out of what it finds.
	// Meant to work with urls of the form: "https://jococruise.com/jonathan-coulton/" 
	// Like all scrapers, this code is fragile to changes in the HTML structure in the page being scraped.
	fileprivate func buildPerformerFromURL(_ urlString: String, on req: Request) async throws -> PerformerData {
		guard let _ = URL(string: urlString) else {
			throw Abort(.badRequest, reason: "Invalid performer URL: \(urlString)")
		}
		let uri = URI(string: urlString)
		var response = try await req.client.get(uri)
		guard let bytes = response.body?.readableBytes, let html = response.body?.readString(length: bytes) else {
			throw Abort(.badRequest, reason: "No HTML returned from URL: \(urlString)")
		}
		var result = PerformerData()
		let doc = try SwiftSoup.parse(html)
		result.youtubeURL = try doc.select("li.et-social-youtube a").first()?.attr("href")
		result.instagramURL = try doc.select("li.et-social-instagram a").first()?.attr("href")
		result.facebookURL = try doc.select("li.et-social-facebook a").first()?.attr("href")
		result.website = try doc.select("li.et-social-google-plus a").first()?.attr("href")
		result.xURL = try doc.select("li.et-social-twitter a").first()?.attr("href")
		result.header.name = try doc.select("div.et_pb_text_0_tb_body div").first()?.text() ?? ""
		result.pronouns = try doc.select("div.et_pb_text_1_tb_body div").first()?.text()
		result.header.photo = try doc.select("div.et_pb_image_0_tb_body img").first()?.attr("src")
		result.yearsAttended = try doc.select("div.et_pb_column_2_tb_body div.et_pb_blurb_description").first()?.text()
				.split(separator: " • ").compactMap( { Int($0) } ) ?? []
		if let bio = try doc.select("div.et_pb_text_2_tb_body div").first() {
			result.bio = try processHTMLIntoMarkdown(bio)
		}
		// Clear out any values scraped from the page footer (they're all JoCo links, not specific to this performer)
		if result.youtubeURL == "https://www.youtube.com/jococruise" {
			result.youtubeURL = nil
		}
		if result.instagramURL == "https://www.instagram.com/jococruise/" {
			result.instagramURL = nil
		}
		if result.facebookURL == "https://www.facebook.com/JoCoCruise" {
			result.facebookURL = nil
		}
		return result
	}
	
	// A really bad implementation of HTML to Markdown. Only works with a few Markdonw tags, but these seem to be the only
	// ones used by the Performer Bio html sections on jococruise.com.
	// 
	// Any HTML tags not recognized and converted into their Markdown equivalent are removed from the output.
	fileprivate func processHTMLIntoMarkdown(_ rootNode: Node) throws  -> String {
		let accum = StringBuilder()
        var nextNode: Node = rootNode
        var parentStack: [(Node, String)] = [(rootNode, "")]

		traversal: while true {
	        let curNode = nextNode
	        var tailText: String = ""
            if let textNode = curNode as? TextNode {
				accum.append(textNode.getWholeText())
            } else if let element = (curNode as? Element) {
				switch element.tagName() {
					case "strong": accum.append("**"); tailText = "**"
					case "i", "em": accum.append("*"); tailText = "*"
					case "p": tailText = "\n"
					case "a": accum.append("["); tailText = try "](\(element.attr("href")))"
					default: break
				}
            }
            if curNode.childNodeSize() > 0 {
                nextNode = curNode.childNode(0)
                parentStack.append((curNode, tailText))
			} else {
				accum.append(tailText)
				while true {
					if let node = nextNode.nextSibling() {
						nextNode = node
						break
					}
 					if parentStack.isEmpty {
						break traversal
					}
					else {
						var tail: String
						(nextNode, tail) = parentStack.removeLast()
						accum.append(tail)
					}
				}
            }
        }
        return accum.toString()
    }
}

// Used to create a PerformerUploadData from the web form. Used in a couple of places.
extension PerformerUploadData {
	fileprivate init(form: AddPerformerFormContent, photo: ImageUploadData, overrideIsOfficial: Bool? = nil ) {
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
		isOfficialPerformer = overrideIsOfficial ?? form.isOfficialPerformer ?? true
		yearsAttended = form.yearsAttended?.matches(of: #/20\d\d/#).compactMap { Int($0.output) }.sorted() ?? []
	}
}
