import Vapor
import Crypto
import FluentSQL

struct EventPageContext : Encodable {
	struct CruiseDay : Encodable {
		var name: String				// "Sun", "Mon", etc.
		var index: Int					// [0...7] For a Saturday...Saturday cruise, embark is day 0, return is day 7.
		var activeDay: Bool
	}
	var trunk: TrunkContext
	var events: [EventData]
	var days: [CruiseDay]
	var isBeforeCruise: Bool
	var isAfterCruise: Bool
	var upcomingEvent: EventData?
	var filterString: String
	var useAllDays: Bool
	var cruiseStartDate: Date
	var cruiseEndDate: Date
	var webcalURL: String

	init(_ req: Request, events: [EventData], dayOfCruise: Int, filterString: String, allDays: Bool) {
		self.events = events
		trunk = .init(req, title: "Events", tab: .events, search: "Search Events")
		isBeforeCruise = Date() < Settings.shared.cruiseStartDate()
		isAfterCruise = Date() > Settings.shared.getPortCalendar().date(byAdding: .day, value: Settings.shared.cruiseLengthInDays, 
				to: Settings.shared.cruiseStartDate()) ?? Date()

		// Set up the day buttons, one for each day of the cruise.		
		let daynames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
		days = Array<CruiseDay>()
		for dayIndex in 1...Settings.shared.cruiseLengthInDays {
			let weekday = (Settings.shared.cruiseStartDayOfWeek + dayIndex - 2) % 7
			days.append(CruiseDay(name: daynames[weekday], index: dayIndex - 1, activeDay: dayIndex == dayOfCruise))
		}

		if let _ = trunk.alertCounts.nextFollowedEventTime {
			let secondsPerWeek = 60 * 60 * 24 * 7
			let partialWeek = Int(Date().timeIntervalSince(Settings.shared.cruiseStartDate())) % secondsPerWeek
			let dateInCruiseWeek = Settings.shared.cruiseStartDate() + TimeInterval(partialWeek)
			upcomingEvent = events.first {
				return $0.isFavorite && ((-5 * 60)...(15 * 60)).contains(dateInCruiseWeek.timeIntervalSince($0.startTime))
			}
		}
		self.filterString = filterString
		self.useAllDays = allDays
		self.cruiseStartDate = Settings.shared.cruiseStartDate()
		var dateComponent = DateComponents()
		dateComponent.day = Settings.shared.cruiseLengthInDays
		self.cruiseEndDate = Calendar.current.date(byAdding: dateComponent, to: cruiseStartDate) ?? cruiseStartDate
		
		// Set up a special URL that will open in calendaring apps.
		if let user = req.auth.get(UserCacheData.self), 
				let username = user.username.percentEncodeFilePathEntry() {
			self.webcalURL = "webcal://\(Settings.shared.canonicalHostnames.first ?? "")/events/subscribe/\(username)/following.ics"
		}
		else {
			self.webcalURL = ""
		}
	}
}

struct SiteEventsController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .schedule))
		openRoutes.get("events", use: eventsPageHandler)
		openRoutes.get("events", eventIDParam, use: eventGetPageHandler)
		openRoutes.get("events", eventIDParam, "calendarevent.ics", use: eventsDownloadICSHandler)
		
		// The route calendar subscriptions use to poll for their .ics file. Has special middleware needs.
		let calendaringRoute = app.grouped([DisabledSiteSectionMiddleware(feature: .schedule),
				CalendarSessionFixerMiddleware(), 	// Adds a path component to the session cookie after sessions.middleware sets it
				app.sessions.middleware, 			// Gets session data from Redis; sets cookie on responses
				UserCacheData.SessionAuth(),		// Auths a UserCacheData based on the session data from Redis
				Token.authenticator()])				// For apps that want to sometimes open web pages
		calendaringRoute.get("events", "subscribe", usernameParam, "following.ics", use: eventsDownloadFollowingHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .schedule))
		privateRoutes.post("events", eventIDParam, "favorite", use: eventsAddRemoveFavoriteHandler)
		privateRoutes.delete("events", eventIDParam, "favorite", use: eventsAddRemoveFavoriteHandler)
	}
	
// MARK: - Events
	/// `GET /events`
	///
	/// By default, shows a day's worth events. Always attempts to show events from a day on the actual cruise. Uses
	/// `Settings.shared.cruiseStartDate` for cruise dates; the ingested schedule should have events for that day and
	/// the next 7 days.
	///
	/// Use the 'day' or 'cruiseday' query parameter to request which day to show. If no parameter given, uses the
	/// current day of week.
	///
	/// When the search parameter is used, returns events for the entire cruise, that match the search value.
	///
	/// Query Parameters:
	/// - day=STRING      One of: "sun" ... "sat". Can also use "1sat" for first Saturday (embarkation day), or "2sat" for the next Saturday.
	/// - cruiseday=INT   Generally 1...8, where 1 is embarkation day.
	/// - search=STRING   Filter only events that match the given string.
	func eventsPageHandler(_ req: Request) async throws -> View {
		var components = URLComponents()
		components.queryItems = []
		var dayOfCruise: Int = -1
		var filterString = "Events"
		var useAllDays: Bool = false
		
		if let searchParam = req.query[String.self, at: "search"] {
			components.queryItems?.append(URLQueryItem(name: "search", value: searchParam))
			filterString = "Events matching \"\(searchParam)\""
			useAllDays = true
		}
		if let weekdayParam = req.query[String.self, at: "day"] {
			components.queryItems?.append(URLQueryItem(name: "day", value: weekdayParam))
			var dayOfWeek: Int
			switch weekdayParam {
			case "sun": dayOfWeek = 1
			case "mon": dayOfWeek = 2
			case "tue": dayOfWeek = 3
			case "wed": dayOfWeek = 4
			case "thu": dayOfWeek = 5
			case "fri": dayOfWeek = 6
			case "sat": dayOfWeek = 7
			default: dayOfWeek = 7
			}
			dayOfCruise = (7 + dayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7 + 1
		}
		else if let cruisedayParam = req.query[Int.self, at: "cruiseday"] {
			components.queryItems?.append(URLQueryItem(name: "cruiseday", value: String(cruisedayParam)))
			dayOfCruise = cruisedayParam
		}
		else if components.queryItems?.isEmpty == true {
			let cal = Settings.shared.calendarForDate(Date())
			let thisWeekday = cal.component(.weekday, from: Date())
			dayOfCruise = (7 + thisWeekday - Settings.shared.cruiseStartDayOfWeek) % 7 + 1
			components.queryItems?.append(URLQueryItem(name: "cruiseday", value: String(dayOfCruise)))
			filterString = "Today's " + filterString
		}

		let response = try await apiQuery(req, endpoint: "/events", query: components.queryItems, passThroughQuery: false)
		let events: [EventData] = try response.content.decode([EventData].self)
		
		let eventContext = EventPageContext(req, events: events, dayOfCruise: dayOfCruise, 
				filterString: filterString, allDays: useAllDays)
		return try await req.view.render("events", eventContext)
	}

	// `GET /events/:event_id`
	//
	// Show a particular event. This shares a lot of minor functionality with the eventsPageHandler above
	// regarding the day of the week, etc.
	func eventGetPageHandler(_ req: Request) async throws -> View {
		var events: [EventData] = []
		var dayOfCruise: Int = -1
		let filterString = "Event"
		let useAllDays: Bool = false
		let cal = Settings.shared.calendarForDate(Date())

		var thisWeekday = cal.component(.weekday, from: Date())
		if let eventID = req.parameters.get(eventIDParam.paramString)?.percentEncodeFilePathEntry() {
			let response = try await apiQuery(req, endpoint: "/events/\(eventID)")
			let event = try response.content.decode(EventData.self)
			events.append(event)
			thisWeekday = cal.component(.weekday, from: event.startTime)
		}

		dayOfCruise = (7 + thisWeekday - Settings.shared.cruiseStartDayOfWeek) % 7 + 1

		let eventContext = EventPageContext(req, events: events, dayOfCruise: dayOfCruise, 
				filterString: filterString, allDays: useAllDays)
		return try await req.view.render("events", eventContext)
	}
	
	// `GET /events/:event_id/calendarevent.ics`
	//
	// Returns a .ics file containing info on the given event; suitable for opening in calendaring apps.
	func eventsDownloadICSHandler(_ req: Request) async throws -> Response {
		guard let eventID = req.parameters.get(eventIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing event ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/events/\(eventID)")
		let event = try response.content.decode(EventData.self)
		let username = req.auth.get(UserCacheData.self)?.username ?? ""
		let icsString = buildEventICS(events: [event], username: username)
		let cleanEventTitle = event.title.replacingOccurrences(of: "\"", with: "")
		let headers = HTTPHeaders([("Content-Disposition", "attachment; filename=\"\(cleanEventTitle).ics\"")])
		return try await icsString.encodeResponse(status: .ok, headers: headers, for: req)
	}
	
	// `GET /events/following.ics`
	//
	// Returns a .ics file containing info on the events the user is following; suitable for opening in calendaring apps.
	// When 
	func eventsDownloadFollowingHandler(_ req: Request) async throws -> Response {
		// This part of the handler should probably be done in middleware. Implements the HTTP Basic Auth flow, including
		// returning 401 Unauthorized with a response header indicating we'd accept basic auth, and using the Authorization
		// header to log the user in. 
		if req.auth.get(UserCacheData.self) == nil, let basicAuthHeader = req.headers.first(name: "Authorization") {
			var loginHeaders = HTTPHeaders()
			loginHeaders.add(name: "Authorization", value: basicAuthHeader)
			let response = try await apiQuery(req, endpoint: "/auth/login", method: .POST, defaultHeaders: loginHeaders)
			let tokenResponse = try response.content.decode(TokenStringData.self)
			// on iOS, the user-agent from Calendar is: User-Agent: iOS/16.3.1 (20D67) dataaccessd/1.0
			try await SiteLoginController().loginUser(with: tokenResponse, on: req, defaultDeviceType: "Calendaring App")
		}
		// Ensures that a user is logged in, and that user matches the one named in the request path. Else -> 401.
		guard let user = req.auth.get(UserCacheData.self), 
				let username = req.parameters.get(usernameParam.paramString)?.removingPercentEncoding,
				user.username == username else {
			req.session.destroy()
			var apiHeaders = HTTPHeaders()
			apiHeaders.add(name: "WWW-Authenticate", value: "Basic charset=\"UTF-8\"")
			let resp = Response(status: .unauthorized, headers: apiHeaders)
			return resp
		}
 		
		let response = try await apiQuery(req, endpoint: "/events/favorites")
		let events = try response.content.decode([EventData].self)
		let icsString = buildEventICS(events: events, username: user.username)
		let cleanEventTitle = "JoCo Cruise: \(user.username)"
		let headers = HTTPHeaders([("Content-Disposition", "attachment; filename=\"\(cleanEventTitle).ics\""),
				("Content-Type", "text/calendar; charset=utf-8")])
		return try await icsString.encodeResponse(status: .ok, headers: headers, for: req)
	}

	// Glue code that calls the API to favorite/unfavorite an event. Returns 201/204 on success.
	func eventsAddRemoveFavoriteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let eventID = req.parameters.get(eventIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing event ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/events/\(eventID)/favorite", method: req.method)
		return response.status
	}
	
// MARK: - Utility fns

	/// Creates a iCalendar data file describing the given event. iCalendar is also known as VCALENDAR or an .ics file.
	/// It's the thing most calendar event importers have standardized on for data interchange.
	func buildEventICS(events: [EventData], username: String = "") -> String {
		let yearFormatter = DateFormatter()
		yearFormatter.setLocalizedDateFormatFromTemplate("y")
		let cruiseYear = yearFormatter.string(from: Settings.shared.cruiseStartDate())
		var resultICSString = """
				BEGIN:VCALENDAR
				VERSION:2.0
				X-WR-CALNAME:JoCo Cruise \(cruiseYear): \(username)
				X-WR-CALDESC:Event Calendar
				METHOD:PUBLISH
				CALSCALE:GREGORIAN
				PRODID:-//Sched.com JoCo Cruise \(cruiseYear)//EN
				X-WR-TIMEZONE:UTC
				
				"""
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [ .withYear, .withMonth, .withDay, .withTime, .withTimeZone ]
		for event in events {
			let startTime = dateFormatter.string(from: event.startTime)
			let endTime = dateFormatter.string(from: event.endTime)
			let stampTime = dateFormatter.string(from: event.lastUpdateTime )		// DTSTAMP is when the ICS was last modified.
			resultICSString.append("""
					BEGIN:VEVENT
					DTSTAMP:\(stampTime)
					DTSTART:\(startTime)
					DTEND:\(endTime)
					SUMMARY:\(icsEscapeString(event.title))
					DESCRIPTION:\(icsEscapeString(event.description))
					CATEGORIES:\(icsEscapeString(event.eventType))
					LOCATION:\(icsEscapeString(event.location))
					SEQUENCE:0
					UID:\(icsEscapeString(event.uid))
					URL:https://jococruise\(cruiseYear).sched.com/event/\(event.uid)
					END:VEVENT
					
					""")
		}
		resultICSString.append("""
				END:VCALENDAR
				
				""")
		return resultICSString
	}
	
	// the ICS file format has specific string escaping requirements. See https://datatracker.ietf.org/doc/html/rfc5545
	func icsEscapeString(_ str: String) -> String {
		let result = str.replacingOccurrences(of: "\\", with: "\\\\")
				.replacingOccurrences(of: ";", with: "\\;")
				.replacingOccurrences(of: ",", with: "\\,")
				.replacingOccurrences(of: "\n", with: "\\n")
		return result
	}
}

// A specialized middleware just for the ics route that Calendaring apps use. This middleware is inserted before the
// SessionMiddleware that sets the session cookie, and it's job is to modify the cookie's domain path.
struct CalendarSessionFixerMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		let response = try await next.respond(to: request)
		if var sessionCookie = response.cookies["swiftarr_session"], let user = request.auth.get(UserCacheData.self),
				let username = user.username.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) {
			sessionCookie.path = "/events/subscribe/\(username)"
			response.cookies["swiftarr_session"] = sessionCookie
		}
		return response
    }
}
    
