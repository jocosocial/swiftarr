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
		
		// Shutternaut event scheduling--for 'nauts to schedule which events they'll be photographing
		tokenAuthGroup.post(eventIDParam, "needsphotographer", use: needsPhotographerHandler).setUsedForPreregistration()
		tokenAuthGroup.post(eventIDParam, "needsphotographer", "remove", use: needsPhotographerHandler).setUsedForPreregistration()
		tokenAuthGroup.delete(eventIDParam, "needsphotographer", use: needsPhotographerHandler).setUsedForPreregistration()
		tokenAuthGroup.post(eventIDParam, "photographer", use: photographerAddHandler).setUsedForPreregistration()
		tokenAuthGroup.post(eventIDParam, "photographer", "remove", use: photographerRemoveHandler).setUsedForPreregistration()
		tokenAuthGroup.delete(eventIDParam, "photographer", use: photographerRemoveHandler).setUsedForPreregistration()
	}

	// MARK: - Open Access Handlers
	// The handlers in this route group do not require Authorization, but can take advantage
	// of Authorization headers if they are present.

	/// `GET /api/v3/events`
	///
	/// Retrieve a list of scheduled events. By default, this retrieves the entire event schedule.
	///
	/// **URL Query Parameters:**
	/// - cruiseday=INT				Embarkation day is day 1, value should be  less than or equal to `Settings.shared.cruiseLengthInDays`, which will be 8 for the 2022 cruise.
	/// - day=STRING				3 letter day of week abbreviation e.g. "TUE" .Returns events for that day *of the cruise in 2022* "SAT" returns events for embarkation day while
	/// 								the current date is earlier than embarkation day, then it returns events for disembarkation day.
	/// - ?date=DATE				Returns events occurring on the given day. Empty list if there are no cruise events on that day.
	/// - ?time=DATE				Returns events whose startTime is earlier (or equal) to DATE and endTime is later than DATE. Note that this will often include 'all day' events.
	/// - ?type=[official, shadow]	Only returns events matching the selected type.
	/// - ?search=STRING			Returns events whose title or description contain the given string.
	/// - ?location=STRING			Returns events whose room name contains the given string.
	/// - ?following=TRUE			Returns events the user is following, aka favorited.
	/// - ?dayplanner=TRUE			Returns events that should appear in the user's day planner. Currently this includes events
	/// 								the user's following and events they signed up to photograph.
	/// 
	/// **Query Parameters for Shutternauts Only**
	/// - needsPhotographer=BOOL	Returns events that a ShutternautManager has marked as needing a photograher.
	/// - hasPhotographer=BOOL		Returns events that have a photographer assigned, including self-assigns
	/// 
	/// Needing a photographer and having one are orthogonal values--filtering for 'needsPhotograher' will return events that already
	/// have a photographer assigned.
	///
	/// The `?day=STRING` query parameter is intended to make it easy to get schedule events returned even when the cruise is not occurring, for ease of testing.
	/// The day and date parameters actually return events from 3AM local time on the given day until 3AM the next day--some events start after midnight and tend to get lost by those
	/// looking at daily schedules.
	///
	/// All the above parameters filter the set of `EventData` objects that get returned. Onlly one of [cruiseday, day, date, time] may be used.
	///
	/// - Returns: An array of `EventData` containing filtered events.
	func eventsHandler(_ req: Request) async throws -> [EventData] {
		struct QueryOptions: Content {
			var cruiseday: Int?
			var day: String?
			var date: Date?
			var time: Date?
			var type: String?
			var search: String?
			var location: String?
			var following: Bool?
			var dayplanner: Bool?
			var needsPhotographer: Bool?
			var hasPhotographer: Bool?
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
		if var location = options.location {
			// postgres "_" and "%" are wildcards, so escape for literals
			location = location.replacingOccurrences(of: "_", with: "\\_").replacingOccurrences(of: "%", with: "\\%")
					.trimmingCharacters(in: .whitespacesAndNewlines)
			query.filter(\.$location ~~ location)
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
		
		let user = req.auth.get(UserCacheData.self)
		if let user {
			if options.following == true {
				query.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
						.filter(EventFavorite.self, \.$user.$id == user.userID)
						.filter(EventFavorite.self, \.$favorite == true)
			}
			if options.dayplanner == true {
				query.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
						.filter(EventFavorite.self, \.$user.$id == user.userID)
			}
			if user.userRoles.contains(.shutternaut) || user.userRoles.contains(.shutternautmanager) {
				if let np = options.needsPhotographer {
					query.filter(\.$needsPhotographer == np)
				}
				if options.hasPhotographer == true {
					query.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
							.filter(EventFavorite.self, \.$photographer == true)
				}
				else if options.hasPhotographer == false {
					query.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id, method: .left)
							.filter(\.$needsPhotographer == true)
							.filter(EventFavorite.self, \EventFavorite.$id == .null)
				}
			}
			else if options.needsPhotographer != nil || options.hasPhotographer != nil {
				throw Abort(.badRequest, reason: "Only Shutternauts can view photograper event data")
			}
		}
		else if options.following == true || options.dayplanner == true {
			throw Abort(.badRequest, reason: "Must be logged in to view favorite events or the dayplanner")
		}
		else if options.needsPhotographer != nil || options.hasPhotographer != nil {
			throw Abort(.badRequest, reason: "Must be logged in as a Shutternaut to view photograper event data")
		}
		let events = try await query.all()
		let favoriteEventIDs = try await getFavorites(in: req, from: events)
		let photographedEvents = try await getShutternautsForEvents(in: req, from: events)
		var builtEventIDs: Set<UUID> = []
		let result: [EventData] = try events.compactMap { 
			guard try builtEventIDs.insert($0.requireID()).inserted else {
				return nil
			}
			var resultEvent = try EventData($0, isFavorite: favoriteEventIDs.contains($0.requireID()))
			if let user, user.userRoles.contains(.shutternaut) || user.userRoles.contains(.shutternautmanager) {
				let photographers = try photographedEvents[$0.requireID()] ?? []
				resultEvent.shutternautData = .init(needsPhotographer: $0.needsPhotographer, photographers: photographers,
						userIsPhotographer: photographers.contains { $0.userID == user.userID })
			}
			return resultEvent
		}
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
		var result = try EventData(event, isFavorite: false)
		if let user = req.auth.get(UserCacheData.self) {
			result.isFavorite = try await EventFavorite.query(on: req.db).filter(\.$user.$id == user.userID)
					.filter(\.$event.$id == event.requireID()).first() != nil
			if user.userRoles.contains(.shutternaut) || user.userRoles.contains(.shutternautmanager) {
				let photographers = try await EventFavorite.query(on: req.db).filter(\.$event.$id == event.requireID())
						.filter(\.$photographer == true).all().map { try req.userCache.getHeader($0.$user.id) }
				result.shutternautData = .init(needsPhotographer: event.needsPhotographer, photographers: photographers,
						userIsPhotographer: photographers.contains { $0.userID == user.userID })
			}
		}
		return result
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
		let user = try req.auth.require(UserCacheData.self)
		let event = try await Event.findFromParameter(eventIDParam, on: req)
		if let fav = try await EventFavorite.query(on: req.db).filter(\.$event.$id == event.requireID())
				.filter(\.$user.$id == user.userID).first() {
			if fav.favorite {
				return .ok
			}
			fav.favorite = true
			try await fav.save(on: req.db)
			_ = try await storeNextFollowedEvent(userID: user.userID, on: req)
			return .created
		}
		let newFav = try EventFavorite(user.userID, event)
		try await newFav.save(on: req.db)
		_ = try await storeNextFollowedEvent(userID: user.userID, on: req)
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
		let user = try req.auth.require(UserCacheData.self)
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Invalid event ID parameter")
		}
		if let favoriteEvent = try await EventFavorite.query(on: req.db).filter(\.$user.$id == user.userID)
				.filter(\.$event.$id == eventID).first() {
			let wasFavorited = favoriteEvent.favorite
			if favoriteEvent.photographer {
				favoriteEvent.favorite = false
				try await favoriteEvent.save(on: req.db)
			}
			else {
				try await favoriteEvent.delete(on: req.db)
			}
			_ = try await storeNextFollowedEvent(userID: user.userID, on: req)
			return wasFavorited ? .noContent : .ok
		} 
		return .ok
	}

	/// `GET /api/v3/events/favorites`
	///
	/// Retrieve the `Event`s the user has favorited, sorted by `.startTime`.
	///
	/// - Returns: An array of `EventData` containing the user's favorite events.
	func favoritesHandler(_ req: Request) async throws -> [EventData] {
		let user = try req.auth.require(UserCacheData.self)
		let events = try await Event.query(on: req.db)
				.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
				.filter(EventFavorite.self, \.$user.$id == user.userID)
				.filter(EventFavorite.self, \.$favorite == true)
				.sort(\.$startTime, .ascending)
				.all()
		let photographedEvents = try await getShutternautsForEvents(in: req, from: events)
		return try events.map { 
			var resultEvent = try EventData($0, isFavorite: true)
			if user.userRoles.contains(.shutternaut) || user.userRoles.contains(.shutternautmanager) {
				let photographers = try photographedEvents[$0.requireID()] ?? []
				resultEvent.shutternautData = .init(needsPhotographer: $0.needsPhotographer, photographers: photographers,
						userIsPhotographer: photographers.contains { $0.userID == user.userID })
			}
			return resultEvent
		}
	}
		
	/// `POST /api/v3/events/:event_ID/needsphotographer`
	/// `POST /api/v3/events/:event_ID/needsphotographer/remove`
	/// `DELETE /api/v3/events/:event_ID/needsphotographer`
	///
	/// Sets or clears the `needsPhotographer` flag on the given event. May only be called by members of the `shutternautManager` group.
	///
	/// - Parameter eventID: in URL path
	/// - Returns: 200 OK if flag is set/cleared successfully.
	func needsPhotographerHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.userRoles.contains(.shutternautmanager) else {
			throw Abort(.forbidden, reason: "Only Shutternaut Managers may set/clear this")
		}
		let event = try await Event.findFromParameter(eventIDParam, on: req)
		event.needsPhotographer = !(req.method == .DELETE || req.url.path.hasSuffix("remove"))
		try await event.save(on: req.db)
		return .ok
	}

	/// `POST /api/v3/events/ID/photographer`
	///
	/// Marks the current user as attending the given event as a photographer. Only callable by members of the `shutternaut` group.
	/// This method is how shutternauts can self-report that they're going to be covering an event and taking pictures.
	///
	/// - Parameter eventID: in URL path
	/// - Returns: 201 Created on success; 200 OK if already marked as photographing the given event.
	func photographerAddHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		let event = try await Event.findFromParameter(eventIDParam, on: req)
		if let fav = try await EventFavorite.query(on: req.db).filter(\.$event.$id == event.requireID())
				.filter(\.$user.$id == user.userID).first() {
			if fav.photographer {
				return .ok
			}
			fav.photographer = true
			try await fav.save(on: req.db)
			_ = try await storeNextFollowedEvent(userID: user.userID, on: req)
			return .created
		}
		let newFav = try EventFavorite(user.userID, event)
		newFav.favorite = false
		newFav.photographer = true
		try await newFav.save(on: req.db)
		_ = try await storeNextFollowedEvent(userID: user.userID, on: req)
		return .created
	}

	/// `POST /api/v3/events/ID/photographer/remove`
	/// `DELETE /api/v3/events/ID/photographer`
	///
	/// Remove the specified `Event` from the user's list of events they'll be photographing. 
	/// Only callable by members of the `shutternaut` group.
	///
	/// - Parameter eventID: in URL path
	/// - Returns: 204 No Content on success; 200 OK if event is already not marked.
	func photographerRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Invalid event ID parameter")
		}
		if let favoriteEvent = try await EventFavorite.query(on: req.db).filter(\.$user.$id == user.userID)
				.filter(\.$event.$id == eventID).first() {
			let wasPhotog = favoriteEvent.photographer
			if favoriteEvent.favorite {
				favoriteEvent.photographer = false
				try await favoriteEvent.save(on: req.db)
			}
			else {
				try await favoriteEvent.delete(on: req.db)
			}
			_ = try await storeNextFollowedEvent(userID: user.userID, on: req)
			return wasPhotog ? .noContent : .ok
		} 
		return .ok
	}
	
	// MARK: Utilities

	func getFavorites(in req: Request, from events: [Event]? = nil) async throws -> Set<UUID> {
		guard let cacheUser = req.auth.get (UserCacheData.self) else {
			return Set()
		}
		let query = EventFavorite.query(on: req.db).filter(\.$user.$id == cacheUser.userID).filter((\.$favorite == true))
		if let events = events {
			try query.filter(\.$event.$id ~~ events.map { try $0.requireID() })
		}
		return try await Set(query.all().map { $0.$event.id })
	}
	
	func getShutternautsForEvents(in req: Request, from events: [Event]) async throws -> [UUID : [UserHeader]] {
		guard let user = req.auth.get (UserCacheData.self), 
				user.userRoles.contains(.shutternaut) || user.userRoles.contains(.shutternautmanager) else {
			return [:]
		}
		let eventIDs = try events.map { try $0.requireID() }
		let shutternauts = try await EventFavorite.query(on: req.db).filter(\.$event.$id ~~ eventIDs).filter(\.$photographer == true).all()
		let result = try shutternauts.reduce(into: [UUID: [UserHeader]]()) { result, favorite in
			result[favorite.$event.id, default: []].append(try req.userCache.getHeader(favorite.$user.id))
		}
		return result
	}
}
