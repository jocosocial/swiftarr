import FluentSQL
import Vapor

struct SiteEventFeedbackController: SiteControllerUtils {

	// Form data posted from the Event Feedback form
	struct EventFeedbackFormContent: Codable {
		var eventUID: String
		var eventTitle: String?
		var eventLocation: String?
		var eventTime: Double?			// Stored as a double in a hidden field; prevents timezone and auto-date-conversion issues.

		var reporterName: String
		var attendance: String
		var recapString: String
		var issuesString: String
	}

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .eventFeedback))
		globalRoutes.get("eventfeedback", use: eventSelector).destination("Shadow Event Feedback").setErrorSchemeOverride(htmlErrors: true)
		globalRoutes.get("eventfeedback", "form", eventUIDParam, use: eventFeedbackForm)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .eventFeedback))
		privateRoutes.post("eventfeedback", "form", use: postEventForm)
		privateRoutes.get("eventfeedback", "form", "submitted", use: eventFeedbackFormSubmitted)
		
		// Routes TwitarrTeam and above. If you're not logged in we failscreen.
		let privateTTRoutes = getPrivateRoutes(app, minAccess: .twitarrteam, path: "admin", "eventfeedback")
		privateTTRoutes.get(use: getFeedbackRoot)
		privateTTRoutes.get("reports", use: feedbackReporting)
		privateTTRoutes.get("report", feedbackParam, use: viewReport)
		privateTTRoutes.post("report", feedbackParam, "mark", use: addRemoveActionableMark)
		privateTTRoutes.delete("report", feedbackParam, "mark", use: addRemoveActionableMark)
		privateTTRoutes.get("reports", "table", use: feedbackReporting)
		privateTTRoutes.get("reports", "download", use: downloadReports)	
		privateTTRoutes.get("roomposters", use: roomPosterSelector)
		privateTTRoutes.post("roomposters", use: printRoomPosters)
	}
	
	/// GET /eventfeedback
	/// 
	/// Start of the Shadow Event Feedback flow. First page is where the user chooses the event they're giving feedback on.
	/// Current design is that this page isn't going to have inbound links from the rest of the site; instead the page will
	/// usually be accessed via QR code, with a link structured as: "https://twitarr.com/eventfeedback?room=Stuyvesant"
	func eventSelector(_ req: Request) async throws -> Response {
		// THO has an existing Google Sheets form for collecting shadow event host feedback. If for some reason we need to
		// use that system instead of this one, set this to 'true' and point the redirect at the Google page.
		// This could be done with Settings, but it'd clutter it up and will probably never be used.
		if false {
			return req.redirect(to: "/")
		}
		// Passes '?room=' to API
		let apiCall = try await apiQuery(req, endpoint: "/feedback/eventlist")
		let events = try apiCall.content.decode(EventFeedbackSelectionData.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var events: EventFeedbackSelectionData
			var activeTab: String
			var roomName: String?

			init(_ req: Request, events: EventFeedbackSelectionData) throws {
				trunk = .init(req, title: "Event Feedback", tab: .none)
				self.events = events
				if let roomEvent = events.matchingRoom.first {
					roomName = roomEvent.location
				}
				if !events.performerAttached.isEmpty {
					activeTab = "performer"
				}
				else if !events.matchingRoom.isEmpty {
					activeTab = "room"
				}
				else {
					activeTab = "all"
				}
			}
		}
		var ctx = try PageContext(req, events: events)
		if false {
			ctx.trunk.metaRedirectURL = "/"
		}
		let response = try await req.view.render("Feedback/eventSelector", ctx).encodeResponse(for: req).get()
		return response
	}
	
	/// GET /eventfeedback/form/:event_uid
	/// 
	/// Takes in a user-selected event ID, returns a page with a feedback form.
	func eventFeedbackForm(_ req: Request) async throws -> View {
		guard let eventUID = req.parameters.get(eventUIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing event UID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/feedback/uid/\(eventUID)")
		let existingFeedback = try response.content.decode(EventFeedbackReport.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var isEdit: Bool
			var existing: EventFeedbackReport?
			var formAction: String = "/eventfeedback/form"
			var successURL: String = "/eventfeedback/form/submitted" 
			
			init(_ req: Request, existing: EventFeedbackReport) {
				trunk = .init(req, title: "Event Feedback", tab: .none)
				self.isEdit = existing.reportModDate != nil
				self.existing = existing
			}
		}
		let ctx = PageContext(req, existing: existingFeedback)
		return try await req.view.render("Feedback/feedbackForm", ctx)
	}
	
	/// POST /eventfeedback/form
	/// 
	/// POST for event feedback form.
	func postEventForm(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(EventFeedbackFormContent.self)
		let feedbackData = EventFeedbackData(eventUID: postStruct.eventUID, eventTitle: postStruct.eventTitle ?? "",
				eventLocation: postStruct.eventLocation ?? "", 
				eventTime: Date(timeIntervalSince1970: postStruct.eventTime ?? 0), 
				hostName: postStruct.reporterName, 
				attendance: postStruct.attendance, recapString: postStruct.recapString, issuesString: postStruct.issuesString)
		try await apiQuery(req, endpoint: "/feedback", method: .POST, encodeContent: feedbackData)
		return .created
	}
	
	/// GET /eventfeedback/form/submitted
	/// 
	/// Shows the "Feedback Recieved" flow completion page.
	func eventFeedbackFormSubmitted(_ req: Request) async throws -> View {
		struct PageContext: Encodable {
			var trunk: TrunkContext
			
			init(_ req: Request) {
				trunk = .init(req, title: "Feedback Submitted", tab: .none)
			}
		}
		let ctx = PageContext(req)
		return try await req.view.render("Feedback/feedbackSubmitted", ctx)
	}
	
	// `GET /admin/eventfeedback`
	//
	// Shows a page with actions for Shadow Event Feedback administration
	func getFeedbackRoot(_ req: Request) async throws -> View {
		struct PageContext: Encodable {
			var trunk: TrunkContext
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "Event Feedback Admin Page", tab: .admin)
			}
		}
		let ctx = try PageContext(req)
		return try await req.view.render("Feedback/adminRoot", ctx)
	}
	
	/// GET /admin/eventfeedback/reports
	/// GET /admin/eventfeedback/reports/table
	/// 
	/// Displays all feedback reports from shadow event hosts, either as a list (with links to individual reports) or a table.
	/// 
	/// Query Parameters:
	/// - location=STRING   	Filter reports by room name (actually text search; can use partial names)
	/// - userid=STRING     	Filter reports by Twitarr userID of the reporter
	func feedbackReporting(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/feedback/reports")
		var reports = try response.content.decode([EventFeedbackReport].self)
		let loc = req.query[String.self, at: "location"] 
		if let loc = loc {
			reports = reports.filter { $0.eventLocation.lowercased().contains(loc.lowercased()) }
		}
		let userString = req.query[String.self, at: "userid"]
		var userFilter: String?
		if let userString = userString, let user = UUID(uuidString: userString) {
			reports = reports.filter { $0.reportingUser.userID == user }
			userFilter = reports.first?.reportingUser.username ?? userString
		}
		let statsResponse = try await apiQuery(req, endpoint: "/admin/feedback/stats")
		let stats = try statsResponse.content.decode(EventFeedbackStats.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var reports: [EventFeedbackReport]
			var stats: EventFeedbackStats
			var locationFilter: String?
			var userFilter: String?
			var responsePercentage: String
			
			init(_ req: Request, reports: [EventFeedbackReport], stats: EventFeedbackStats, locationFilter: String?, 
					userFilter: String?) throws {
				trunk = .init(req, title: "Feedback Reports", tab: .admin)
				self.reports = reports
				self.stats = stats
				self.locationFilter = locationFilter
				self.userFilter = userFilter
				let percentage = Double(stats.uniqueEventsWithFeedback) / Double(stats.completedShadowEvents)
				self.responsePercentage = percentage.formatted(.percent.precision(.fractionLength(1)))
			}
		}
		let ctx = try PageContext(req, reports: reports, stats: stats, locationFilter: loc, userFilter: userFilter)
		if req.url.path.contains("table") {
			return try await req.view.render("Feedback/adminReportsTable", ctx)
		}
		return try await req.view.render("Feedback/adminReports", ctx)
	}
	
	/// GET /admin/eventfeedback/report/:report_id
	/// 
	/// Displays a single event feedback report.
	func viewReport(_ req: Request) async throws -> View {
		guard let idString = req.parameters.get(feedbackParam.paramString), let feedbackID = UUID(uuidString: idString) else {
			throw Abort(.badRequest, reason: "Missing feedbackID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/admin/feedback/report/\(feedbackID)")
		let report = try response.content.decode(EventFeedbackReport.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var report: EventFeedbackReport
			var event: EventData?
			var searchLocation: String
			var cruiseStartDate: Date
			var cruiseEndDate: Date
			
			init(_ req: Request, report: EventFeedbackReport) throws {
				trunk = .init(req, title: "Feedback Reports", tab: .admin)
				self.report = report
				self.event = report.event
				self.searchLocation = report.eventLocation.components(separatedBy: ",").first ?? ""
				self.cruiseStartDate = Settings.shared.cruiseStartDate()
				self.cruiseEndDate = Settings.shared.getPortCalendar().date(byAdding: .day, value: Settings.shared.cruiseLengthInDays,
						to: cruiseStartDate) ?? cruiseStartDate
			}
		}
		let ctx = try PageContext(req, report: report)
		return try await req.view.render("Feedback/adminReport", ctx)
	}
		
	/// GET /admin/eventfeedback/reports/download
	/// 
	/// Initiates a download of a .CSV file containing all the Event Feedback Reports.
	func downloadReports(_ req: Request) async throws -> Response {
		func buildCSVRecord(fields: String...) -> String {
			return fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",").appending("\n")
		}
		let response = try await apiQuery(req, endpoint: "/admin/feedback/reports")
		let reports = try response.content.decode([EventFeedbackReport].self)
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "MMM d, h:mm a z"
		let csvHeaderLine = "\u{FEFF}" + buildCSVRecord(fields: "Twitarr Username", "Display Name", "Real Name", "Mod Date", "Event UID", 
				"Event Title", "Location", "Start Time", "Attendance", "Recap", "Issues", "Follow Count", 
				"Forum Post Count", "Actionable")
		let csvString = reports.reduce(into: csvHeaderLine) { str, report in
			var modDateString = "no date"
			if let modDate = report.reportModDate {
				modDateString = dateFormatter.string(from: modDate)
			}
			let eventTimeString = dateFormatter.string(from: report.eventTime)
			str.append(buildCSVRecord(fields: report.reportingUser.username,
					report.reportingUser.displayName ?? "",
					report.hostName,
					modDateString,
					report.event?.uid ?? "",
					report.eventTitle,
					report.eventLocation,
					eventTimeString,
					report.attendance,
					report.recapString,
					report.issuesString,
					"\(report.adminFields?.followCount ?? 0)",
					"\(report.adminFields?.forumPostCount ?? 0)",
					report.adminFields?.actionable == true ? "true" : ""))					
		}
		guard let csvData = csvString.data(using: .utf8) else {
			throw Abort(.internalServerError, reason: "Could not convert CSV String into Data.")
		}
		var headers: HTTPHeaders = [:]
		headers.contentType = HTTPMediaType(type: "text", subType: "csv", parameters: ["charset": "UTF-8"])
		headers.contentDisposition = .init(.attachment, filename: "event_feedback_reports.csv")
		let body = Response.Body(data: csvData)
		return Response(status: .ok, headers: headers, body: body)
	}

	/// POST /admin/eventfeedback/report/:report_id/mark
	/// DELETE /admin/eventfeedback/report/:report_id/mark
	///
	/// Adds or rmoves an 'actionable' mark to the specified feedback report. 
	/// Returns 201/204 on success.
	func addRemoveActionableMark(_ req: Request) async throws -> HTTPStatus {
		guard let feedbackIDString = req.parameters.get(feedbackParam.paramString), let feedbackID = UUID(uuidString: feedbackIDString) else {
			throw Abort(.badRequest, reason: "Missing feedback ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/admin/feedback/report/\(feedbackID)/mark", method: req.method)
		return response.status
	}

	/// GET /admin/eventfeedback/roomposters
	/// 
	/// Displays a form pre-filled with all the room names that are hosting shadow events, scraped from the schedule.
	/// After editing, this will go to a print-optimized HTML document with one room poster per page. Each room poster has
	/// the name of the room, instructions for the host, and a QR code that goes to the feedback flow.
	/// The URL embedded in each QR code has a query option specifying the room name, which allows the event selector page to 
	/// filter the list of events to those happening in that room.
	func roomPosterSelector(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/feedback/roomlist")
		let roomList = try response.content.decode([String].self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var rooms: String
			var formAction: String = "/admin/eventfeedback/roomposters"
			
			init(_ req: Request, roomList: [String]) {
				trunk = .init(req, title: "Shadow Event Room Names", tab: .none)
				rooms = roomList.joined(separator: "\n")
			}
		}
		let ctx = PageContext(req, roomList: roomList)
		return try await req.view.render("Feedback/roomPosterForm", ctx)
	}
	
	/// POST /admin/eventfeedback/roomposters
	/// 
	/// The POST form in the request contents contains a list of all the room names for which to print signs.
	/// Returns an HTML page meant to be printed out onto letter-size paper (one sheet per room name), 
	/// and taped up to the walls of various rooms on the ship.
	/// 
	/// The returned page uses special css for printing, but doesn't contain a 'Print' button that opens the print dialog in the browser.
	/// 
	/// Each sheet contains a QR Code, and the URL encoded in that QR code has the form 
	/// "https://twitarr.com/eventfeedback?room=Rolling+Stone+Lounge", but with appropriate room names. The URL encoded in the QR Code
	/// is always twitarr.com no matter what the current hostname is.
	func printRoomPosters(_ req: Request) async throws -> View {
		struct RoomPosterForm: Content {
			var roomNames: String
		}
		let postStruct = try req.content.decode(RoomPosterForm.self)
		let roomNamesArray = postStruct.roomNames.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
				.compactMap { $0.isEmpty ? nil : $0 }
				
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var rooms: [RoomInfo]
			var year: String
			
			init(_ req: Request, roomNames: [String]) throws {
				trunk = .init(req, title: "Shadow Event Room Names", tab: .none)
				rooms = try roomNames.map { try RoomInfo(name: $0) }
				if let currentYear = Settings.shared.cruiseStartDateComponents.year {
					year = "\(currentYear)"
				}
				else {
					year = "2026"
				}

			}
		}
		let ctx = try PageContext(req, roomNames: roomNamesArray)
		return try await req.view.render("Feedback/roomPosterPrint", ctx)
	}
	
	// Used to pass info on rooms to Leaf templates.
	struct RoomInfo: Encodable {
		var name: String
		var qrCodeURL: String			// This is the URL to get the image from the server, NOT the URL the QR Code contains
		
		// Takes the name of a room on the ship where Shadow Events will be held.
		//
		// In this function:
		// 		urlInQRComponents is the URL encoded in the QR Code--the thing you decode using your phone camera
		//		imageLinkComponents is the URL to the image of the QR Code--designed to be used e.g. in an <img> tag.
		init(name: String) throws {
			self.name = name
			guard var urlInQRComponents = URLComponents(string: "https://twitarr.com/eventfeedback") else {
				throw Abort(.internalServerError, reason: "Couldn't create URLComponents from static string.")
			}
			urlInQRComponents.queryItems = [URLQueryItem(name: "room", value: name)]
			guard let urlInQRCode = urlInQRComponents.string else {
				throw Abort(.internalServerError, reason: "Couldn't create URL from components.")
			}
			var imageLinkComponents = Settings.shared.canonicalServerURLComponents
			imageLinkComponents.path = "/api/v3/image/qrcode"
			imageLinkComponents.queryItems = [URLQueryItem(name: "string", 
					value: urlInQRCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)]
			guard let urlToQRCode = imageLinkComponents.string else {
				throw Abort(.internalServerError, reason: "Couldn't create URL to QR Code image from components.")
			}
			self.qrCodeURL = urlToQRCode		
		}
	}
	
}
