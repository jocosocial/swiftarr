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
        let optionalAuthGroup = addFlexAuthGroup(to: eventRoutes)
        optionalAuthGroup.get(use: eventsHandler)
        optionalAuthGroup.get(eventIDParam, use: singleEventHandler)
        
        // endpoints available only when logged in
        let tokenAuthGroup = addTokenAuthGroup(to: eventRoutes)
        tokenAuthGroup.post(eventIDParam, "favorite", use: favoriteAddHandler)
        tokenAuthGroup.post(eventIDParam, "favorite", "remove", use: favoriteRemoveHandler)
        tokenAuthGroup.delete(eventIDParam, "favorite", use: favoriteRemoveHandler)
        tokenAuthGroup.get("favorites", use: favoritesHandler)
        tokenAuthGroup.post("update", use: eventsUpdateHandler)
    }
    
    // MARK: - Open Access Handlers
    // The handlers in this route group do not require Authorization, but can take advantage
    // of Authorization headers if they are present.

    /// `GET /api/v3/events`
    ///
    /// Retrieve a list of scheduled events. By default, this retrieves the entire event schedule.
	/// 
	/// Query Parameters:
	/// - cruiseday=INT		Embarkation day is day 1, value should be  less than or equal to `Settings.shared.cruiseLengthInDays`, which will be 8 for the 2022 cruise.
	/// - day=STRING			3 letter day of week abbreviation e.g. "TUE" .Returns events for that day *of the cruise in 2022* "SAT" returns events for embarkation day while 
	/// 					the current date is earlier than embarkation day, then it returns events for disembarkation day.
	/// - ?date=DATE			Returns events occurring on the given day. Empty list if there are no cruise events on that day.
	/// - ?time=DATE			Returns events whose startTime is earlier (or equal) to DATE and endTime is later than DATE. Note that this will often include 'all day' events.
	/// - ?type=[official, shadow]	Only returns events matching the selected type. 
	/// - ?match=STRING		Returns events whose title or description contain the given string.
	/// 
	/// The `?day=STRING` query parameter is intended to make it easy to get schedule events returned even when the cruise is not occurring, for ease of testing.. 
	/// The day and date parameters actually return events from 3AM on the given day until 3AM the next day--some events start after midnight and tend to get lost by those
	/// looking at daily schedules.
	/// 
	/// All the above parameters filter the set of `EventData` objects that get returned. Onlly one of [day, date, time] may be used.  
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all events.
    func eventsHandler(_ req: Request) throws -> EventLoopFuture<[EventData]> {
    	struct QueryOptions: Content {
			var cruiseday: Int?
			var day: String?
			var date: Date?
			var time: Date?
			var type: String?
			var match: String?
    	}
    	let options = try req.query.decode(QueryOptions.self)
    	let query = Event.query(on: req.db).sort(\.$startTime, .ascending)
        if var search = options.match {
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
		serverCalendar.timeZone = req.application.environment == .testing ? TimeZone(abbreviation: "EST")! : TimeZone.autoupdatingCurrent
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
			return (req.auth.get(User.self)?.getBookmarkBarrel(of: .taggedEvent, on: req) ?? req.eventLoop.future(nil))
				.flatMapThrowing { eventsBarrel in
				let result = try events.map { try EventData($0, isFavorite: eventsBarrel?.modelUUIDs.contains($0.requireID()) ?? false) }
				return result
			}
		}
    }
    
    /// `GET /api/v3/events/ID`
    ///
    /// Retrieve a single event from its ID.
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `EventData` containing  event info.
    func singleEventHandler(_ req: Request) throws -> EventLoopFuture<EventData> {
    	return Event.findFromParameter(eventIDParam, on: req).flatMap { event in
			return (req.auth.get(User.self)?.getBookmarkBarrel(of: .taggedEvent, on: req) ?? req.eventLoop.future(nil))
					.flatMapThrowing { eventsBarrel in
	    		return try EventData(event, isFavorite: eventsBarrel?.modelUUIDs.contains(event.requireID()) ?? false)
			}
    	}
    }

    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/events/update`
    ///
    /// Updates the `Event` database from an `.ics` file.
    ///
    /// - Requires: `EventUpdateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `EventUpdateData` containing an updated event schedule.
    /// - Throws: 403 Forbidden if the user is not an admin.
    /// - Returns: `[EventData]` containing the events that were updated or added.
    func eventsUpdateHandler(_ req: Request) throws -> EventLoopFuture<[EventData]> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.admin) else {
            throw Abort(.forbidden, reason: "admins only")
        }
        var schedule = try req.content.decode(EventsUpdateData.self).schedule 
        schedule = schedule.replacingOccurrences(of: "&amp;", with: "&")
        schedule = schedule.replacingOccurrences(of: "\\,", with: ",")
        return req.db.transaction { database in
            // convert to [Event]
            let updateEvents = EventParser().parse(schedule)
            let existingEvents = Event.query(on: database).all()
            return existingEvents.flatMap { (events) in
                var updatedEvents: [EventLoopFuture<Void>] = []
                for update in updateEvents {
                    let event = events.first(where: { $0.uid == update.uid })
                    // if event exists
                    if let event = event {
                        // update existing event
                        if event.startTime != update.startTime
                            || event.endTime != update.endTime
                            || event.title != update.title
                            || event.info != update.info
                            || event.location != update.location
                            || event.eventType != update.eventType {
                            event.startTime = update.startTime
                            event.endTime = update.endTime
                            event.title = update.title
                            event.info = update.info
                            event.location = update.location
                            event.eventType = update.eventType
                            // save future
                            updatedEvents.append(event.save(on: req.db))
                        }
                    } else {
                        // else create new event
                        let newEvent = Event(
                            startTime: update.startTime,
                            endTime: update.endTime,
                            title: update.title,
                            description: update.info,
                            location: update.location,
                            eventType: update.eventType,
                            uid: update.uid
                        )
                        // save future
                        updatedEvents.append(newEvent.save(on: req.db))
                    }
                }
                
                // Do we delete existing events not in the update?
                
                // resolve futures, return as EventData
                return updatedEvents.flatten(on: req.eventLoop).flatMapThrowing {
					return try updateEvents.map { try EventData($0, isFavorite: false) }
                }
            }
        }
    }
    
    /// `POST /api/v3/events/ID/favorite`
    ///
    /// Add the specified `Event` to the user's tagged events list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: 201 Created on success.
    func favoriteAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get event
        return Event.findFromParameter("event_id", on: req).flatMap { (event) in
            guard let eventID = event.id else { return req.eventLoop.makeFailedFuture(FluentError.idRequired) } 
            // get user's taggedEvent barrel
            return Barrel.query(on: req.db)
					.filter(\.$ownerID == userID)
					.filter(\.$barrelType == .taggedEvent)
					.first()
					.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .taggedEvent))
					.flatMap { (barrel) in
				// add event and return 201
				if !barrel.modelUUIDs.contains(eventID) {
					barrel.modelUUIDs.append(eventID)
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
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the event was not favorited.
    /// - Returns: 204 No Content on success.
    func favoriteRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get event
        return Event.findFromParameter("event_id", on: req).flatMap { (event) in
            guard let eventID = event.id else { return req.eventLoop.makeFailedFuture(FluentError.idRequired) } 
            // get user's taggedEvent barrel
            return Barrel.query(on: req.db)
					.filter(\.$ownerID == userID)
					.filter(\.$barrelType == .taggedEvent)
					.first()
					.flatMap { (eventBarrel) in
				guard let barrel = eventBarrel else {
					return req.eventLoop.makeFailedFuture(
							Abort(.badRequest, reason: "user has not tagged any events"))
				}
				// remove event
				guard let index = barrel.modelUUIDs.firstIndex(of: eventID) else {
					return req.eventLoop.makeFailedFuture(
							Abort(.badRequest, reason: "event was not tagged"))
				}
				barrel.modelUUIDs.remove(at: index)
				return barrel.save(on: req.db).transform(to: .noContent)
			}
        }
    }
    
    /// `GET /api/v3/events/favorites`
    ///
    /// Retrieve the `Event`s in the user's taggedEvent barrel, sorted by `.startTime`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing the user's favorited events.
    func favoritesHandler(_ req: Request) throws -> EventLoopFuture<[EventData]> {
        let user = try req.auth.require(User.self)
        // get user's taggedEvent barrel
        return user.getBookmarkBarrel(of: .taggedEvent, on: req).flatMap { (barrel) in
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
}
