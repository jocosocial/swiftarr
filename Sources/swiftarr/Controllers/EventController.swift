import Fluent
import FluentSQL
import Vapor
import CoreXLSX

/// The collection of `/api/v3/events/*` route endpoints and handler functions related
/// to the event schedule.

struct EventController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/users endpoints
		let eventRoutes = app.grouped("api", "v3", "events")

		// Flexible access endpoints that behave differently for logged-in users
		let optionalAuthGroup = eventRoutes.flexRoutes(feature: .schedule)
		optionalAuthGroup.get(use: eventsHandler).setUsedForPreregistration()
		optionalAuthGroup.get(eventIDParam, use: singleEventHandler).setUsedForPreregistration()

		// endpoints available only when logged in
		let tokenAuthGroup = eventRoutes.tokenRoutes(feature: .schedule)
		tokenAuthGroup.post(eventIDParam, "favorite", use: favoriteAddHandler).setUsedForPreregistration()
		tokenAuthGroup.post(eventIDParam, "favorite", "remove", use: favoriteRemoveHandler).setUsedForPreregistration()
		tokenAuthGroup.delete(eventIDParam, "favorite", use: favoriteRemoveHandler).setUsedForPreregistration()
		tokenAuthGroup.get("favorites", use: favoritesHandler).setUsedForPreregistration()
	}

	// MARK: - Open Access Handlers
	// The handlers in this route group do not require Authorization, but can take advantage
	// of Authorization headers if they are present.

	/// `GET /api/v3/events`
	///
	/// Retrieve a list of scheduled events. By default, this retrieves the entire event schedule.
	///
	/// **URL Query Parameters:**
	/// - cruiseday=INT		Embarkation day is day 1, value should be  less than or equal to `Settings.shared.cruiseLengthInDays`, which will be 8 for the 2022 cruise.
	/// - day=STRING			3 letter day of week abbreviation e.g. "TUE" .Returns events for that day *of the cruise in 2022* "SAT" returns events for embarkation day while
	/// 					the current date is earlier than embarkation day, then it returns events for disembarkation day.
	/// - ?date=DATE			Returns events occurring on the given day. Empty list if there are no cruise events on that day.
	/// - ?time=DATE			Returns events whose startTime is earlier (or equal) to DATE and endTime is later than DATE. Note that this will often include 'all day' events.
	/// - ?type=[official, shadow]	Only returns events matching the selected type.
	/// - ?search=STRING		Returns events whose title or description contain the given string.
	///
	/// The `?day=STRING` query parameter is intended to make it easy to get schedule events returned even when the cruise is not occurring, for ease of testing.
	/// The day and date parameters actually return events from 3AM local time on the given day until 3AM the next day--some events start after midnight and tend to get lost by those
	/// looking at daily schedules.
	///
	/// All the above parameters filter the set of `EventData` objects that get returned. Onlly one of [cruiseday, day, date, time] may be used.
	///
	/// - Returns: An array of  `EventData` containing filtered events.
	func eventsHandler(_ req: Request) async throws -> [EventData] {
		struct QueryOptions: Content {
			var cruiseday: Int?
			var day: String?
			var date: Date?
			var time: Date?
			var type: String?
			var search: String?
		}
		let options = try req.query.decode(QueryOptions.self)
		let query = Event.query(on: req.db).sort(\.$startTime, .ascending)
		if !Settings.shared.disabledFeatures.isFeatureDisabled(.performers) {
			query.with(\.$performers)
		}
		if var search = options.search {
			// postgres "_" and "%" are wildcards, so escape for literals
			search = search.replacingOccurrences(of: "_", with: "\\_")
			search = search.replacingOccurrences(of: "%", with: "\\%")
			search = search.trimmingCharacters(in: .whitespacesAndNewlines)
			query.group(.or) { (or) in
				or.fullTextFilter(\.$title, search)
				or.fullTextFilter(\.$info, search)
			}
		}
		if let eventType = options.type {
			if eventType == "shadow" {
				query.filter(\.$eventType == .shadow)
			}
			else {
				query.filter(\.$eventType != .shadow)
			}
		}
		// Events are stored as 'floating' times in the portTimeZone. So, filtering against dates calculated in portTimeZone
		// should do the right thing, even when the dates are then adjusted to the current TZ for delivery.
		let portCalendar = Settings.shared.getPortCalendar()
		// For the purpose of events, 'days' start at midnight and end at 3 AM the next day in the Port timezone.
		let cruiseStartDate = Settings.shared.cruiseStartDate()
		var searchStartTime: Date?
		var searchEndTime: Date?
		let addDayPlusThreeHours = DateComponents(day: 1, hour: 3)
		if let day = options.day {
			var cruiseDayIndex: Int
			let embarkDayOfWeek = (Settings.shared.cruiseStartDayOfWeek - 1)
			switch day.prefix(3).lowercased() {
			case "sun": cruiseDayIndex = (7 - embarkDayOfWeek) % 7
			case "mon": cruiseDayIndex = (8 - embarkDayOfWeek) % 7
			case "tue": cruiseDayIndex = (9 - embarkDayOfWeek) % 7
			case "wed": cruiseDayIndex = (10 - embarkDayOfWeek) % 7
			case "thu": cruiseDayIndex = (11 - embarkDayOfWeek) % 7
			case "fri": cruiseDayIndex = (12 - embarkDayOfWeek) % 7
			case "sat": cruiseDayIndex = (13 - embarkDayOfWeek) % 7
			case "1sa": cruiseDayIndex = (13 - embarkDayOfWeek) % 7
			case "2sa": cruiseDayIndex = ((13 - embarkDayOfWeek) % 7) + 7
			case "1su": cruiseDayIndex = ((7 - embarkDayOfWeek) % 7)
			case "2su": cruiseDayIndex = ((7 - embarkDayOfWeek) % 7) + 7
			default: cruiseDayIndex = 0
			}
			searchStartTime = portCalendar.date(byAdding: .day, value: cruiseDayIndex, to: cruiseStartDate)
			if let searchStartTime {
				searchEndTime = portCalendar.date(byAdding: addDayPlusThreeHours, to: searchStartTime)
			}
		}
		else if let cruiseday = options.cruiseday {
			searchStartTime = portCalendar.date(byAdding: .day, value: cruiseday - 1, to: cruiseStartDate)
			if let searchStartTime {
				searchEndTime = portCalendar.date(byAdding: addDayPlusThreeHours, to: searchStartTime)
			}
		}
		else if let date = options.date {
			// Get a date that's the midnight just before the given date, in the ship's port timezone
			searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime(searchStartTime)
			searchStartTime = portCalendar.startOfDay(for: date)
			if let searchStartTime {
				searchEndTime = portCalendar.date(byAdding: addDayPlusThreeHours, to: searchStartTime)
			}
		}
		else if let time = options.time {
			let portTime = Settings.shared.timeZoneChanges.displayTimeToPortTime(time)
			query.filter(\.$startTime <= portTime).filter(\.$endTime > portTime)
		}
		if let start = searchStartTime, let end = searchEndTime {
			query.filter(\.$startTime >= start).filter(\.$startTime < end)
		}
		let events = try await query.all()
		let favoriteEventIDs = try await getFavorites(in: req, from: events)
		let result = try events.map { try EventData($0, isFavorite: favoriteEventIDs.contains($0.requireID())) }
		return result
	}

	/// `GET /api/v3/events/ID`
	///
	/// Retrieve a single event from its database ID or event UID. UID is part of the ICS spec for calendar events (RFC 5545).
	///
	/// - Parameter eventID: in URL path
	/// - Returns: `EventData` containing  event info.
	func singleEventHandler(_ req: Request) async throws -> EventData {
		guard let paramVal = req.parameters.get(eventIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Event is missing.")
		}
		var event: Event?
		if let paramUUID = UUID(paramVal) {
			event = try await Event.query(on: req.db).filter(\._$id == paramUUID).first()
		}
		if event == nil {
			event = try await Event.query(on: req.db).filter(\.$uid == paramVal).first()
		}
		guard let event = event else {
			throw Abort(.notFound, reason: "No event with this UID or database ID found.")
		}
		if !Settings.shared.disabledFeatures.isFeatureDisabled(.performers) {
			let _ = try await event.$performers.get(on: req.db)
		}
		
		var isFavorite = false
		if let user = req.auth.get(UserCacheData.self) {
			isFavorite = try await EventFavorite.query(on: req.db).filter(\.$user.$id == user.userID)
				.filter(\.$event.$id == event.requireID()).first() != nil
		}
		return try EventData(event, isFavorite: isFavorite)
	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

	/// `POST /api/v3/events/ID/favorite`
	///
	/// Add the specified `Event` to the user's tagged events list.
	///
	/// - Parameter eventID: in URL path
	/// - Returns: 201 Created on success; 200 OK if already favorited.
	func favoriteAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let user = try await User.find(cacheUser.userID, on: req.db) else {
			throw Abort(.internalServerError, reason: "User in cache but not found in User table")
		}
		let event = try await Event.findFromParameter(eventIDParam, on: req)
		if try await event.$favorites.isAttached(to: user, on: req.db) {
			return .ok
		}
		try await event.$favorites.attach(user, on: req.db)
		_ = try await storeNextFollowedEvent(userID: cacheUser.userID, on: req)
		return .created
	}

	/// `POST /api/v3/events/ID/favorite/remove`
	/// `DELETE /api/v3/events/ID/favorite`
	///
	/// Remove the specified `Event` from the user's tagged events list.
	///
	/// - Parameter eventID: in URL path
	/// - Throws: 400 error if the event was not favorited.
	/// - Returns: 204 No Content on success; 200 OK if event is already not favorited.
	func favoriteRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Invalid event ID parameter")
		}
		if let favoriteEvent = try await EventFavorite.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.filter(\.$event.$id == eventID).first()
		{
			try await favoriteEvent.delete(on: req.db)
			_ = try await storeNextFollowedEvent(userID: cacheUser.userID, on: req)
			return .noContent
		}
		return .ok
	}

	/// `GET /api/v3/events/favorites`
	///
	/// Retrieve the `Event`s the user has favorited, sorted by `.startTime`.
	///
	/// - Returns: An array of  `EventData` containing the user's favorite events.
	func favoritesHandler(_ req: Request) async throws -> [EventData] {
		let user = try req.auth.require(UserCacheData.self)
		let events = try await Event.query(on: req.db)
			.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
			.filter(EventFavorite.self, \.$user.$id == user.userID).sort(\.$startTime, .ascending).all()
		return try events.map { try EventData($0, isFavorite: true) }
	}
	
	// MARK: Utilities

	func getFavorites(in req: Request, from events: [Event]? = nil) async throws -> Set<UUID> {
		guard let cacheUser = req.auth.get (UserCacheData.self) else {
			return Set()
		}
		let query = EventFavorite.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
		if let events = events {
			try query.filter(\.$event.$id ~~ events.map { try $0.requireID() })
		}
		return try await Set(query.all().map { $0.$event.id })
	}
}
