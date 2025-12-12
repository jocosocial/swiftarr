import FluentSQL
import LeafKit
import Vapor

// Form data from the Create/Update Private Event form
struct CreatePrivateEventPostFormContent: Codable {
	var subject: String
	var location: String
	var starttime: String
	var duration: Int
	var postText: String
	var inviteOthers: String?
	var participants: String  // Comma separated list of participant usernames
}

struct PrivateEventListPageContext: Encodable {
	var trunk: TrunkContext
	var fezList: FezListData
	var fezzes: [FezData]
	var effectiveUser: String?
	var paginator: PaginatorContext
	var query: PrivateEventQueryOptions
	var queryDescription: String

	init(_ req: Request, fezList: FezListData, fezzes: [FezData]) throws {
		trunk = .init(req, title: "Private Events", tab: .home)
		self.fezList = fezList
		self.fezzes = fezzes
		let limit = fezList.paginator.limit
		let searchQuery = try req.query.decode(PrivateEventQueryOptions.self)
		query = searchQuery
		queryDescription = query.describeQuery()
		if query.search != nil {
			paginator = .init(fezList.paginator) { pageIndex in
				return searchQuery.buildQuery(baseURL: "/seamail/search", startOffset: pageIndex * limit) ?? "/seamail/search"
			}
		}
		else {
			paginator = .init(fezList.paginator) { pageIndex in
				"/seamail?start=\(pageIndex * limit)&limit=\(limit)"
			}
		}
	}
}

struct PrivateEventQueryOptions: Content {
	var search: String?
	var start: Int?
	var limit: Int?
	var onlynew: Bool?
	
	func describeQuery() -> String {
		return "\(onlynew == true ? "New " : "")Private Events\(search != nil ? " containing \"\(search!)\"" : "")"
	}

	// Builds a new URL given the saved query options plus the given baseURL and startOffset. Used
	// to build paginator links.
	func buildQuery(baseURL: String, startOffset: Int?) -> String? {
		guard var components = URLComponents(string: baseURL) else {
			return nil
		}
		// We don't expose the type=open&type=closed paramters here because they could
		// get overridden elsewhere.
		var elements = [URLQueryItem]()
		if let search = search { elements.append(URLQueryItem(name: "search", value: search)) }
		let newOffset = max(startOffset ?? start ?? 0, 0)
		if newOffset != 0 { elements.append(URLQueryItem(name: "start", value: String(newOffset))) }
		if let limit = limit { elements.append(URLQueryItem(name: "limit", value: String(limit))) }
		if let onlynew = onlynew { elements.append(URLQueryItem(name: "onlynew", value: String(onlynew))) }

		components.queryItems = elements
		return components.string
	}
}


struct SitePrivateEventController: SiteControllerUtils {

	enum AppointmentColor: String, Codable {
		case redTeam
		case goldTeam
		case schedule			// Blue
		case lfg				// Green
		case personalEvent		// Purple?
		case photographer		// Gray
		case blankItem
	}
	
	class AppointmentVisualData: Codable {
		var title: String
		var startTime: Date				// Not necessarily the underlying event/LFG/PE's start and end time
		var endTime: Date
		var concurrentCount: Int = 0
		var rowCount: Int = 0
		var columnCount: Int = 0
		var topMargin: Int = 0
		var bottomMargin: Int = 0
		var color: AppointmentColor
		var link: String?
		
		init?(lfg: FezData) {
			guard let start = lfg.startTime, let end = lfg.endTime else {
				return nil
			}
			title = lfg.cancelled ? "CANCELLED - \(lfg.title)" : lfg.title
			startTime = start
			endTime = end
			if lfg.fezType.isLFGType {
				color = .lfg
			}
			else {
				color = .personalEvent
			}
			link = "/lfg/\(lfg.fezID)"
		}
		
		init(event: EventData) {
			title = event.title
			startTime = event.startTime
			endTime = event.endTime
			if event.shutternautData?.userIsPhotographer == true {
				// photographing's color takes precedence over red/gold or followed events
				color = .photographer
			}
			else if event.title.range(of: "Gold Team", options: .caseInsensitive) != nil {
				color = .goldTeam
			}
			else if event.title.range(of: "Red Team", options: .caseInsensitive) != nil {
				color = .redTeam
			}
			else {
				// User favorited the event
				color = .schedule
			}
			link = "/events/\(event.eventID)"
		}
	
		// Creates 'filler' cells because HTML tables go wonky with sparse td elements.
		init(cols: Int) {
			title = ""
			startTime = Date()
			endTime = Date()
			rowCount = 1
			concurrentCount = 0
			columnCount = cols
			color = .blankItem
			link = nil
		}
		
		func adjustStartEndTimes(dayStart: Date, dayEnd: Date) -> Self? {
			// Remove this item if it doesn't intersect the day's displayed times
			guard endTime > dayStart, startTime < dayEnd, startTime < endTime else {
				return nil
			}
			// Increase displayed length of very short events so their text is legible.
			if endTime.timeIntervalSince(startTime) < 20.0 * 60.0 {
				endTime = startTime + 20.0 * 60.0
			}
			// Clip start and end to the day's displayed times
			if startTime < dayStart {
				startTime = dayStart
			}
			if endTime > dayEnd {
				endTime = dayEnd
			}
			// Calculate how many table rows this item needs to span
			let cal = Settings.shared.calendarForDate(startTime)
			var startTimeComponents = cal.dateComponents(in: cal.timeZone, from: startTime)
			topMargin = ((startTimeComponents.minute ?? 0) % 30) * 25 / 30
			startTimeComponents.minute = startTimeComponents.minute ?? 0 >= 30 ? 30 : 0
			let startRowTime = cal.date(from: startTimeComponents) ?? startTime
			rowCount = Int(ceil(endTime.timeIntervalSince(startRowTime) / (30.0 * 60.0)))
			let endTimeComponents = cal.dateComponents(in: cal.timeZone, from: endTime)
			bottomMargin = ((60 - (endTimeComponents.minute ?? 0)) % 30) * 25 / 30
			return self
		}
	}

	struct TableRow: Codable {
		var hour: String?
		var timezone: String?
		var date: Date
		var newAppointments: [AppointmentVisualData]
		
		init() {
			date = Date()
			newAppointments = []
		}
	}

	func registerRoutes(_ app: Application) throws {
		// Routes that the user needs to be logged in to access.
		let globalRoutes = getGlobalRoutes(app, feature: .personalevents, path: "dayplanner")
		globalRoutes.get("", use: showDayPlanner).destination("the day planner").setUsedForPreregistration()
		globalRoutes.get("subscribe", use: dayplannerSubscribeExplainer).destination("the day planner subscription page")
		globalRoutes.get("shutternauts", use: showDayPlanner).destination("the Shutternaut day planner").setUsedForPreregistration()
		
		let globalPERoutes = getGlobalRoutes(app, feature: .personalevents, path: "privateevent")
		globalPERoutes.get(fezIDParam, use: privateEventPageHandler).destination("private event")

		let privateRoutes = getPrivateRoutes(app, feature: .personalevents, path: "privateevent")
		privateRoutes.get("create", use: peCreatePageHandler)
		privateRoutes.post("create", use: peCreateOrUpdatePostHandler)
		privateRoutes.get(fezIDParam, "update", use: peUpdatePageHandler)
		privateRoutes.post(fezIDParam, "update", use: peCreateOrUpdatePostHandler)
		privateRoutes.get("list", use: peListHandler)

		// This route is intended for calendar apps, allowing for subscriptions to iCal calendar feeds.
		let calendaringRoute = app.grouped([
				CalendarSessionFixerMiddleware(),  // Adds a path component to the session cookie after sessions.middleware sets it
				app.sessions.middleware,  // Gets session data from Redis; sets cookie on responses
				UserCacheData.SessionAuth(),  // Auths a UserCacheData based on the session data from Redis
				UserCacheData.BasicAuth(),
				Token.authenticator(),
				DisabledSiteSectionMiddleware(feature: .personalevents),
		])
		calendaringRoute.get("dayplanner", usernameParam, "jocoDayPlanner.ics", use: calendarDownload)
	}
	
	// GET /dayplanner						The user's events, LFGs, private events, personal events
	// GET /dayplanner/shutternauts			Events any Shutternaut has signed up to photograph. Only usable by Shutternauts.
	//
	/// **URL Query Parameters:**
	/// - cruiseday=INT		Embarkation day is day 1, value should be  less than or equal to `Settings.shared.cruiseLengthInDays`, which will be 8 for the 2022 cruise.
	func showDayPlanner(_ req: Request) async throws -> View {
		let dayOfWeek = Settings.shared.calendarForDate(Date()).component(.weekday, from: Date())
		var cruiseDay: Int
		var eventParams = [URLQueryItem]()
		var lfgParams = [URLQueryItem]()
		if let day = req.query[Int.self, at: "cruiseday"] {
			cruiseDay = day
		}
		else {
			cruiseDay = (7 + dayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7 + 1
		}
		let shutternautSharedSchedule = req.url.path == "/dayplanner/shutternauts"
					
		eventParams.append(URLQueryItem(name: "cruiseday", value: "\(cruiseDay)"))
		lfgParams.append(URLQueryItem(name: "cruiseday", value: "\(cruiseDay-1)"))
		if shutternautSharedSchedule {
			eventParams.append(URLQueryItem(name: "hasPhotographer", value: "true"))
		}
		else {
			eventParams.append(URLQueryItem(name: "dayplanner", value: "true"))
		}
		let eventsResponse = try await apiQuery(req, endpoint: "/events", query: eventParams, passThroughQuery: false)
		let events = try eventsResponse.content.decode([EventData].self)

		var lfgs: FezListData? = nil
		if !shutternautSharedSchedule && !Settings.shared.enablePreregistration {
			let lfgResponse = try await apiQuery(req, endpoint: "/fez/joined", query: lfgParams +
					[URLQueryItem(name: "excludetype", value: "open"), URLQueryItem(name: "excludetype", value: "closed")], passThroughQuery: false)
			lfgs = try lfgResponse.content.decode(FezListData.self)
		}

		struct DayPlannerPageContext: Encodable {
			var trunk: TrunkContext
			var dayStart: Date
			var dayEnd: Date
			var titleText: String
			let previousDayLink: String?
			let nextDayLink: String?
			var rows: [TableRow]
			var shutternautSharedSchedule: Bool

			init(_ req: Request, cruiseDay: Int, events: [EventData], lfgs: FezListData?) {
				trunk = .init(req, title: "Day Planner", tab: .home)
				let cal = Settings.shared.getPortCalendar()
				dayStart = cal.date(byAdding: .day, value: cruiseDay - 1, to: Settings.shared.cruiseStartDate()) ?? Date()
				dayStart = Settings.shared.timeZoneChanges.portTimeToDisplayTime(dayStart)
				dayEnd = dayStart.addingTimeInterval(27 * 60 * 60) // Generally 3 AM the next day; specifically 27 hours later.
				let dateFormatter = DateFormatter()
				dateFormatter.dateFormat = "EEEE, MMMM d"
				dateFormatter.timeZone = Settings.shared.timeZoneChanges.tzAtTime(dayStart)
				let currentPath = req.url.path
				previousDayLink = cruiseDay <= 1 ? nil : "\(currentPath)?cruiseday=\(cruiseDay - 1)"
				nextDayLink = cruiseDay >= Settings.shared.cruiseLengthInDays ? nil : "\(currentPath)?cruiseday=\(cruiseDay + 1)"
				rows = []
				titleText = dateFormatter.string(from: dayStart)
				shutternautSharedSchedule = req.url.path == "/dayplanner/shutternauts"
				let avds = generateAVDs(events: events, lfgs: lfgs, dayStart: dayStart, dayEnd: dayEnd)
				rows = generateTableRows(forCruiseDay: cruiseDay, avds: avds)
				// for testing the red horizontal rule 'Current Time' indicator
				if false {
					dayStart = Calendar.current.startOfDay(for: Date())
					dayEnd = Calendar.current.startOfDay(for: Date().addingTimeInterval(27 * 60 * 60))
				}
			}
			
			func generateAVDs(events: [EventData], lfgs: FezListData?, dayStart: Date, dayEnd: Date) -> [AppointmentVisualData] {
				var appointments = events.map { AppointmentVisualData(event: $0) }
				if (lfgs != nil) {
					appointments += lfgs!.fezzes.compactMap { AppointmentVisualData(lfg: $0) }
				}
				appointments = appointments.compactMap { $0.adjustStartEndTimes(dayStart: dayStart, dayEnd: dayEnd) }
				var group = [AppointmentVisualData]()
				var columnEndTimes = [Date]()
				var groupEndTime = Date.distantPast
				let sorted = appointments.sorted(by: { $0.startTime < $1.startTime })
				// Figure out how many columns we need for each 'group' of overlapping appointments.
				for appt in sorted {
					if groupEndTime <= appt.startTime {
						// Previous Group complete. Every group member gets the same concurrentCount and will draw with that many columns.
						for groupedAppt in group {
							groupedAppt.concurrentCount = columnEndTimes.count
							switch groupedAppt.concurrentCount {
								case 0, 1: groupedAppt.columnCount = 12
								case 2: groupedAppt.columnCount = 6
								case 3: groupedAppt.columnCount = 4
								case 4: groupedAppt.columnCount = 3
								default: groupedAppt.columnCount = 2
							}
						}
						columnEndTimes = []
						groupEndTime = Date.distantPast
						group.removeAll()
					}
					if let colIndex = columnEndTimes.firstIndex(where: { $0 <= appt.startTime }) {
						// Add new appt to existing column
						columnEndTimes[colIndex] = appt.endTime
					}
					else {
						// Add new column
						columnEndTimes.append(appt.endTime)
					}
					groupEndTime = max(groupEndTime, appt.endTime)
					group.append(appt)
				}
				// Close out the last group
				for groupedAppt in group {
					groupedAppt.concurrentCount = columnEndTimes.count
					switch groupedAppt.concurrentCount {
						case 0, 1: groupedAppt.columnCount = 12
						case 2: groupedAppt.columnCount = 6
						case 3: groupedAppt.columnCount = 4
						case 4: groupedAppt.columnCount = 3
						default: groupedAppt.columnCount = 2
					}
				}
				return sorted
			}
			
			func generateTableRows(forCruiseDay: Int, avds: [AppointmentVisualData]) -> [TableRow] {
				var cal = Calendar(identifier: .gregorian)
				cal.timeZone = Settings.shared.portTimeZone
				var rowTime = cal.date(byAdding: .day, value: forCruiseDay - 1, to: Settings.shared.cruiseStartDate()) ?? Settings.shared.cruiseStartDate()
				rowTime = Settings.shared.timeZoneChanges.portTimeToDisplayTime(rowTime)
				let dateFormatter = DateFormatter()
				dateFormatter.dateFormat = "h a"
				var result = [TableRow]()
				// 1 Day 3 Hours, half hour increments 
				for index in 0..<(27 * 2) {
					guard let nextRowTime = cal.date(byAdding: .minute, value: 30, to: rowTime) else {
						break
					}
					var row = TableRow()
					row.date = rowTime
					row.newAppointments = avds.filter {$0.startTime >= rowTime && $0.startTime < nextRowTime }
					let continuingAppointments = avds.filter { $0.startTime < rowTime && $0.endTime > rowTime }
					if let modelAppt = row.newAppointments.first ?? continuingAppointments.first {
						let fillerCellCount = max(0, modelAppt.concurrentCount - row.newAppointments.count - continuingAppointments.count)
						for _ in 0..<fillerCellCount {
							row.newAppointments.append(.init(cols: modelAppt.columnCount))
						}
					}
					else {
						// Empty row
						row.newAppointments.append(.init(cols: 12))
					}
					let tz = Settings.shared.timeZoneChanges.tzAtTime(rowTime)
					if index % 2 == 0 {
						dateFormatter.timeZone = tz
						row.hour = dateFormatter.string(from: rowTime)
						row.timezone = tz.abbreviation(for: rowTime) 
					}
					else {
						row.timezone = tz.abbreviation(for: rowTime) 
					}
					result.append(row)
					rowTime = nextRowTime
				}
				return result
			}
		}
		let ctx = DayPlannerPageContext(req, cruiseDay: cruiseDay, events: events, lfgs: lfgs)
		return try await req.view.render("PrivateEvent/dayPlanner", ctx)		
	}
	
	// GET /privateevent/create
	//
	// Shows the Create New Private Event page
	func peCreatePageHandler(_ req: Request) async throws -> View {
		let ctx = try FezCreateUpdatePageContext(req, isPrivateEvent: true)
		return try await req.view.render(ctx.leafPath, ctx)
	}
	
	// GET `/privateevent/ID/update`
	// GET `/privateevent/ID/edit`
	//
	// Shows the Update Private Event page.
	func peUpdatePageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid ID"
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(fezID)")
		let fez = try response.content.decode(FezData.self)
		let ctx = try FezCreateUpdatePageContext(req, fezToUpdate: fez, isPrivateEvent: true)
		return try await req.view.render(ctx.leafPath, ctx)
	}

	// POST /privateevent/create
	// POST /privateevent/ID/update
	// Handles the POST from either the Create Or Update Private Event page
	func peCreateOrUpdatePostHandler(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(CreatePrivateEventPostFormContent.self)
		let fezType: FezType = postStruct.inviteOthers == "on" ? .privateEvent : .personalEvent
		guard postStruct.subject.count > 0 else {
			throw Abort(.badRequest, reason: "Title cannot be empty.")
		}
		let lines = postStruct.postText.replacingOccurrences(of: "\r\n", with: "\r").components(separatedBy: .newlines).count
		guard lines <= 25 else {
			throw Abort(.badRequest, reason: "Messages are limited to 25 lines of text.")
		}
		guard let startTime = dateFromW3DatetimeString(postStruct.starttime) else {
			throw Abort(.badRequest, reason: "Couldn't parse start time")
		}
		let endTime = startTime.addingTimeInterval(TimeInterval(postStruct.duration) * 60.0)
		var participants = postStruct.participants.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
		participants = Array(Set(participants))
		var fezContentData = FezContentData(
			fezType: fezType,
			title: postStruct.subject,
			info: postStruct.postText,
			startTime: startTime,
			endTime: endTime,
			location: postStruct.location,
			minCapacity: 0,
			maxCapacity: 0,
			initialUsers: participants
		)
		var path = "/fez/create"
		if let updatingFezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() {
			path = "/fez/\(updatingFezID)/update"
			let response = try await apiQuery(req, endpoint: "/fez/\(updatingFezID)")
			let fez = try response.content.decode(FezData.self)
			fezContentData.fezType = fez.fezType
		}
		try await apiQuery(req, endpoint: path, method: .POST, encodeContent: fezContentData)
		return .created
	}

	// GET /privateevent/ID
	//
	// Paginated.
	//
	// Shows a single Private Event with all its posts.
	func privateEventPageHandler(_ req: Request) async throws -> View {
		return try await SiteFriendlyFezController().singleFezPageHandler(req)
	}
	
	// GET /privateevent/list
	//
	// Shows the Private Events page, with a list of all events.
	func peListHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/joined", query: [URLQueryItem(name: "type", value: "privateEvent"),
				URLQueryItem(name: "type", value: "personalEvent")])
		let eventList = try response.content.decode(FezListData.self)
		let ctx = try PrivateEventListPageContext(req, fezList: eventList, fezzes: eventList.fezzes)
		return try await req.view.render("PrivateEvent/privateEventList", ctx)
	}
	
	// GET /dayplanner/subscribe
	//
	// Shows a page explaining to the user what calendar subscriptions do, with a button to actually subscribe to the
	// Day Planner calendar.
	//
	// Notes on the webcal:// URL
	//
	// Using the 'webcal' scheme causes the link to open in Apple Calendar in a way that makes Calendar subscribe to the URL, 
	// including asking the user for credentials. An http scheme causes the .ics file to be downloaded and then passed to Calendar, 
	// where it ingests all the  events but does not subscribe for updates.
	//
	// On Mac, the webcal scheme will be treated as 'https', even though you get a 'connection not secure' dialog. So far, this is
	// only an issue for local development builds. On iOS, the webcal scheme will fall back to http if https fails.
	//
	// In my limited testing, Google Calendar really wants to run its subscription serverside, via a google.com link with a "?cid=<url>"
	// query item. This won't work on boat even if the user has internet access, as Google can't route to the boat's Twitarr server.
	func dayplannerSubscribeExplainer(_ req: Request) async throws -> View {
		guard let user = req.auth.get(UserCacheData.self),
				let username = user.username.percentEncodeFilePathEntry() else {
			throw Abort(.unauthorized, reason: "Must be logged in to subscribe to Day Planner Calendar.")
		}

		struct SubscribePageContext: Encodable {
			var trunk: TrunkContext
			var currentYear: String
			var webcalURL: String
			
			init(_ req: Request, _ username: String) throws {
				trunk = .init(req, title: "Day Planner Subscribe", tab: .home)
				let yearFormatter = DateFormatter()
				yearFormatter.setLocalizedDateFormatFromTemplate("y")
				self.currentYear = yearFormatter.string(from: Settings.shared.cruiseStartDate())
				var urlComponents = Settings.shared.canonicalServerURLComponents
				urlComponents.scheme = "webcal"
				urlComponents.path = "/dayplanner/\(username)/jocoDayPlanner.ics"
				self.webcalURL = urlComponents.string ?? "webcal://twitarr.com/dayplanner/\(username)/jocoDayPlanner.ics"
			}
		}
		let ctx = try SubscribePageContext(req, username)
		return try await req.view.render("PrivateEvent/subscribe", ctx)
	}
	
	// GET /dayplanner/:username/jocodayplanner.ics
	//
	// Builds and returns an .ics file with the calendar events that appear on the user's Day Planner.
	// The file has the MIME type "text/calendar".
	// This route will often be called by calendaring apps--not browsers.
	//
	// This route allows for login via basic auth and also supports sessions. I believe some calendaring apps don't support
	// pulling data from private calendars and require users to make the calendars public. We're not doing that--don't make this
	// route open to all without creds.
	//
	// Also, Google Calendar (the google-hosted web app) won't work with this, because the Google servers cannot see twittar.com.
	func calendarDownload(_ req: Request) async throws -> Response {
		// Calendar apps almost certainly use ETags or the 'If-Modified-Since' header, but we'd need to cache the last 
		// change time to Redis and update everyone's change time whenever the schedule itself changes.
		// Building the whole response just to compare it to a saved hash probably isn't worth it (the file isn't that big).
		
		// This route uses a custom middleware stack, and we can't use the regular .unauthorized response if we're not authed.
		// For this route we have to add the WWW-Authenticate header to indicate how the client can retry with auth.
		// (regular routes don't do this because they need to go to /login to auth).
		guard let user = req.auth.get(UserCacheData.self) else {
			req.session.destroy()
			var apiHeaders = HTTPHeaders()
			apiHeaders.add(name: "WWW-Authenticate", value: "Basic charset=\"UTF-8\"")
			let resp = Response(status: .unauthorized, headers: apiHeaders)
			return resp
		}
		guard let username = req.parameters.get(usernameParam.paramString)?.removingPercentEncoding, user.username == username else {
			throw Abort(.unauthorized, reason: "Not logged in as the user for this calendar subscription.")
		}
		// If we basic auth'ed on this call (remember: it's the calendar app making the request, not a browser), we should
		// create a session as if they called /login. That is, the calendar app can't know to use the /login route.
		if let basicAuthHeader = req.headers.first(name: "Authorization"), basicAuthHeader.hasPrefix("Basic ") {
			var loginHeaders = HTTPHeaders()
			loginHeaders.add(name: "Authorization", value: basicAuthHeader)
			let response = try await apiQuery(req, endpoint: "/auth/login", method: .POST, defaultHeaders: loginHeaders)
			let tokenResponse = try response.content.decode(TokenStringData.self)
			// on iOS, the user-agent from Calendar is: User-Agent: iOS/16.3.1 (20D67) dataaccessd/1.0
			try await SiteLoginController().loginUser(with: tokenResponse, on: req, defaultDeviceType: "Calendaring App")
		}

		let eventResponse = try await apiQuery(req, endpoint: "/events", query: [URLQueryItem(name: "dayplanner", value: "true")])
		let events = try eventResponse.content.decode([EventData].self)
		let lfgResponse = try await apiQuery(req, endpoint: "/fez/joined", query:
				[URLQueryItem(name: "excludetype", value: "open"), URLQueryItem(name: "excludetype", value: "closed")], passThroughQuery: false)
		let lfgs = try lfgResponse.content.decode(FezListData.self)
		let icsString = ICSHelper.buildICSFile(events: events, lfgs: lfgs.fezzes, username: user.username, contentType: .dayplanner)
		let yearFormatter = DateFormatter()
		yearFormatter.setLocalizedDateFormatFromTemplate("y")
		let year = yearFormatter.string(from: Settings.shared.cruiseStartDate())
		let cleanEventTitle = "JoCo Cruise \(year): \(user.username)"
		let headers = HTTPHeaders([
			("Content-Disposition", "attachment; filename=\"\(cleanEventTitle).ics\""),
			("Content-Type", "text/calendar; charset=utf-8"),
		])
		return try await icsString.encodeResponse(status: .ok, headers: headers, for: req)
	}
}
