import FluentSQL
import LeafKit
import Vapor

enum AppointmentColor: Codable {
	case redTeam(EventData)
	case goldTeam(EventData)
	case schedule(EventData)			// Blue
	case lfg(FezData)			// Green
	case personal(FezData)	// Purple?
}

struct AppointmentVisualData: Codable {
	var startTime: Date
	var endTime: Date
	var concurrentCount: Int
	var column: Int
	var color: AppointmentColor
	
	init?(lfg: FezData) {
		guard let start = lfg.startTime, let end = lfg.endTime else {
			return nil
		}
		startTime = start
		endTime = end
		concurrentCount = 0
		column = 0
		if lfg.fezType.isLFGType {
			color = .lfg(lfg)
		}
		else {
			color = .personal(lfg)
		}
	}
	
	init(event: EventData) {
		startTime = event.startTime
		endTime = event.endTime
		concurrentCount = 0
		column = 0
		if event.description.range(of: "Gold Team", options: .caseInsensitive) != nil {
			color = .goldTeam(event)
		}
		else if event.description.range(of: "Red Team", options: .caseInsensitive) != nil {
			color = .redTeam(event)
		}
		else {
			color = .schedule(event)
		}
	}
}

struct HourMarker: Codable {
	var hour: String
	var timezone: String
	var date: Date
}

struct SiteDayPlannerController: SiteControllerUtils {

	
	func registerRoutes(_ app: Application) throws {
		// Routes that the user needs to be logged in to access.
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .photostream))
		globalRoutes.get("dayplanner", use: showDayPlanner).destination("the day planner")

//		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .photostream))
//		privateRoutes.get("photostream", "report", streamPhotoParam, use: photostreamReportPage)
//		privateRoutes.post("photostream", "report", streamPhotoParam, use: postPhotostreamReport)
	}
	
	// GET /dayplanner
	//
	/// **URL Query Parameters:**
	/// - cruiseday=INT		Embarkation day is day 1, value should be  less than or equal to `Settings.shared.cruiseLengthInDays`, which will be 8 for the 2022 cruise.
	func showDayPlanner(_ req: Request) async throws -> View {
		let dayOfWeek = Settings.shared.calendarForDate(Date()).component(.weekday, from: Date())
		let cruiseDay = req.query[Int.self, at: "cruiseday"] ?? (7 + dayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7 + 1
		let eventsResponse = try await apiQuery(req, endpoint: "/events/favorites", query: [URLQueryItem(name: "cruiseday", value: "\(cruiseDay)")])
		let lfgResponse = try await apiQuery(req, endpoint: "/fez/joined", query: [URLQueryItem(name: "cruiseday", value: "\(cruiseDay)"),
				URLQueryItem(name: "excludetype", value: "open"), URLQueryItem(name: "excludetype", value: "closed")])
		let events = try eventsResponse.content.decode([EventData].self)
		let lfgs = try lfgResponse.content.decode(FezListData.self)
		struct DayPlannerPageContext: Encodable {
			var trunk: TrunkContext
			
			let nextDayLink: String?
			let previousDayLink: String?
			
			var hours: [HourMarker]
			var events: [EventData]
			var lfgs: [FezListData]

			init(_ req: Request, cruiseDay: Int) {
				trunk = .init(req, title: "Day Planner", tab: .home)
				nextDayLink = nil
				previousDayLink = nil
				hours = []
				events = []
				lfgs = []
				hours = generateHourMarkers(forCruiseDay: cruiseDay)
			}
			
			func generateHourMarkers(forCruiseDay: Int) -> [HourMarker] {
				var cal = Calendar(identifier: .gregorian)
				cal.timeZone = Settings.shared.portTimeZone
				var hourTime = cal.date(byAdding: .day, value: forCruiseDay - 1, to: Settings.shared.cruiseStartDate()) ?? Settings.shared.cruiseStartDate()
				hourTime = Settings.shared.timeZoneChanges.portTimeToDisplayTime(hourTime)
				let dateFormatter = DateFormatter()
				dateFormatter.dateFormat = "h a"
				var result = [HourMarker]()
				for index in 0..<27 {
					let tz = Settings.shared.timeZoneChanges.tzAtTime(hourTime)
					dateFormatter.timeZone = tz
					let hourStr = dateFormatter.string(from: hourTime)
					result.append(.init(hour: hourStr, timezone: tz.abbreviation(for: hourTime) ?? "", date: hourTime))
					guard let nextHour = cal.date(byAdding: .hour, value: 1, to: hourTime) else {
						break
					}
					hourTime = nextHour
				}
				return result
			}
		}
		let ctx = DayPlannerPageContext(req, cruiseDay: cruiseDay)
		return try await req.view.render("DayPlanner/dayPlanner", ctx)		
	}
	
}
