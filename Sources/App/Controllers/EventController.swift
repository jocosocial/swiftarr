import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/events/*` route endpoints and handler functions related
/// to the event schedule.

struct EventController: APIRouteCollection {

    /// Required. Registers routes to the incoming router.
    func registerRoutes(_ app: Application) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let eventRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .schedule)).grouped("api", "v3", "events")
        
        // Flexible access endpoints that behave differently for logged-in users
        let optionalAuthGroup = addFlexCacheAuthGroup(to: eventRoutes)
        optionalAuthGroup.get(use: eventsHandler)
        optionalAuthGroup.get(eventIDParam, use: singleEventHandler)
        
        // endpoints available only when logged in
        let tokenAuthGroup = addTokenCacheAuthGroup(to: eventRoutes)
        tokenAuthGroup.post(eventIDParam, "favorite", use: favoriteAddHandler)
        tokenAuthGroup.post(eventIDParam, "favorite", "remove", use: favoriteRemoveHandler)
        tokenAuthGroup.delete(eventIDParam, "favorite", use: favoriteRemoveHandler)
        tokenAuthGroup.get("favorites", use: favoritesHandler)
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
	/// All the above parameters filter the set of <doc:EventData> objects that get returned. Onlly one of [cruiseday, day, date, time] may be used.  
    ///
    /// - Returns: An array of  <doc:EventData> containing filtered events.
    func eventsHandler(_ req: Request) throws -> EventLoopFuture<[EventData]> {
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
        if var search = options.search {
			// postgres "_" and "%" are wildcards, so escape for literals
			search = search.replacingOccurrences(of: "_", with: "\\_")
			search = search.replacingOccurrences(of: "%", with: "\\%")
			search = search.trimmingCharacters(in: .whitespacesAndNewlines)
			query.group(.or) { (or) in
                or.filter(\.$title, .custom("ILIKE"), "%\(search)%")
                or.filter(\.$info, .custom("ILIKE"), "%\(search)%")
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
		var serverCalendar = Calendar(identifier: .gregorian)
		serverCalendar.timeZone = Settings.shared.getDisplayTimeZone()
		// For the purpose of events, 'days' start and end at 3 AM.
		let cruiseStartDate = serverCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate) ??
				Settings.shared.cruiseStartDate
		var searchStartTime: Date?
		var searchEndTime: Date?
		if let day = options.day {
			var cruiseDayIndex: Int
			switch day.prefix(3).lowercased() {
				case "sat": cruiseDayIndex = Date() < cruiseStartDate ? 0 : 7
				case "1sa": cruiseDayIndex = 0
				case "2sa": cruiseDayIndex = 7
				case "sun": cruiseDayIndex = 1
				case "mon": cruiseDayIndex = 2 
				case "tue": cruiseDayIndex = 3
				case "wed": cruiseDayIndex = 4
				case "thu": cruiseDayIndex = 5
				case "fri": cruiseDayIndex = 6
				default: cruiseDayIndex = 0
			}
			searchStartTime = serverCalendar.date(byAdding: .day, value: cruiseDayIndex, to: cruiseStartDate)
			searchEndTime = serverCalendar.date(byAdding: .day, value: cruiseDayIndex + 1, to: cruiseStartDate)
		}
		else if let cruiseday = options.cruiseday {
			searchStartTime = serverCalendar.date(byAdding: .day, value: cruiseday - 1, to: cruiseStartDate)
			searchEndTime = serverCalendar.date(byAdding: .day, value: cruiseday, to: cruiseStartDate)
		}
		else if let date = options.date {
			searchStartTime = serverCalendar.date(byAdding: .hour, value: 3, to: serverCalendar.startOfDay(for: date))
			searchEndTime = serverCalendar.date(byAdding: .day, value: 1, to: searchStartTime ?? cruiseStartDate) 
		}
		else if let time = options.time {
			query.filter(\.$startTime <= time).filter(\.$endTime > time)
		}
		if let start = searchStartTime, let end = searchEndTime {
			query.filter(\.$startTime >= start).filter(\.$startTime < end)
		}
		return query.all().throwingFlatMap { events in
			var barrelFuture: EventLoopFuture<Barrel?> = req.eventLoop.future(nil)
			if let user = req.auth.get(UserCacheData.self) {
				barrelFuture = Barrel.query(on: req.db).filter(\.$ownerID == user.userID).filter(\.$barrelType == .taggedEvent).first()
			}
			return barrelFuture.flatMapThrowing { eventsBarrel in
				let result = try events.map { try EventData($0, isFavorite: eventsBarrel?.modelUUIDs.contains($0.requireID()) ?? false) }
				return result
			}
		}
    }
    
    /// `GET /api/v3/events/ID`
    ///
    /// Retrieve a single event from its ID.
	/// 
    /// - Parameter eventID: in URL path
    /// - Returns: <doc:EventData> containing  event info.
    func singleEventHandler(_ req: Request) throws -> EventLoopFuture<EventData> {
    	return Event.findFromParameter(eventIDParam, on: req).flatMap { event in
			var barrelFuture: EventLoopFuture<Barrel?> = req.eventLoop.future(nil)
			if let user = req.auth.get(UserCacheData.self) {
				barrelFuture = Barrel.query(on: req.db).filter(\.$ownerID == user.userID).filter(\.$barrelType == .taggedEvent).first()
			}
			return barrelFuture.flatMapThrowing { eventsBarrel in
	    		return try EventData(event, isFavorite: eventsBarrel?.modelUUIDs.contains(event.requireID()) ?? false)
			}
    	}
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
    func favoriteAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(UserCacheData.self)
        // get event
        return Event.findFromParameter("event_id", on: req).flatMap { (event) in
            guard let eventID = event.id else { return req.eventLoop.makeFailedFuture(FluentError.idRequired) } 
            // get user's taggedEvent barrel
            return Barrel.query(on: req.db)
					.filter(\.$ownerID == user.userID)
					.filter(\.$barrelType == .taggedEvent)
					.first()
					.unwrap(orReplace: Barrel(ownerID: user.userID, barrelType: .taggedEvent))
					.flatMap { barrel in
				// add event and return 201
				if !barrel.modelUUIDs.contains(eventID) {
					barrel.modelUUIDs.append(eventID)
					_ = storeNextEventTime(userID: user.userID, eventBarrel: barrel, on: req)
				}
				else {
					return req.eventLoop.future(.ok)
				}
				return barrel.save(on: req.db).transform(to: .created)
			}
        }
    }
    
    /// `POST /api/v3/events/ID/favorite/remove`
    /// `DELETE /api/v3/events/ID/favorite`
    ///
    /// Remove the specified `Event` from the user's tagged events list.
    ///
    /// - Parameter eventID: in URL path
    /// - Throws: 400 error if the event was not favorited.
    /// - Returns: 204 No Content on success; 200 OK if event is already not favorited.
    func favoriteRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(UserCacheData.self)
        // get event
        return Event.findFromParameter("event_id", on: req).flatMap { (event) in
            guard let eventID = event.id else { return req.eventLoop.makeFailedFuture(FluentError.idRequired) } 
            // get user's taggedEvent barrel
            return Barrel.query(on: req.db)
					.filter(\.$ownerID == user.userID)
					.filter(\.$barrelType == .taggedEvent)
					.first()
					.flatMap { eventBarrel in
				guard let barrel = eventBarrel else {
					return req.eventLoop.future(.ok)
				}
				// remove event
				guard let index = barrel.modelUUIDs.firstIndex(of: eventID) else {
					return req.eventLoop.future(.ok)
				}
				barrel.modelUUIDs.remove(at: index)
				_ = storeNextEventTime(userID: user.userID, eventBarrel: barrel, on: req)
				return barrel.save(on: req.db).transform(to: .noContent)
			}
        }
    }
    
    /// `GET /api/v3/events/favorites`
    ///
    /// Retrieve the `Event`s in the user's taggedEvent barrel, sorted by `.startTime`.
    ///
    /// - Returns: An array of  <doc:EventData> containing the user's favorite events.
    func favoritesHandler(_ req: Request) throws -> EventLoopFuture<[EventData]> {
        let user = try req.auth.require(UserCacheData.self)
        // get user's taggedEvent barrel
		return Barrel.query(on: req.db).filter(\.$ownerID == user.userID).filter(\.$barrelType == .taggedEvent)
				.first().flatMap { barrel in
            guard let barrel = barrel else {
                // return empty array
                return req.eventLoop.future([EventData]())
            }
            // get events
            return Event.query(on: req.db)
					.filter(\.$id ~~ barrel.modelUUIDs)
					.sort(\.$startTime, .ascending)
					.all()
					.flatMapThrowing { (events) in
				return try events.map { try EventData($0, isFavorite: true) }
            }
        }
    }
    
// MARK: Utilities

}
