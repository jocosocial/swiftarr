import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/events/*` route endpoints and handler functions related
/// to the event schedule.

struct EventController: RouteCollection, ContentFilterable, UserTaggable {
    // MARK: UserTaggable Conformance
    
    /// The barrel type for `Event` favoriting.
    var taggedBarrelType: BarrelType {
        return .taggedEvent
    }
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let eventRoutes = router.grouped("api", "v3", "events")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set unprotected route group
        let openAuthGroup = eventRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware])

        // set protected route groups
        let sharedAuthGroup = eventRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = eventRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        openAuthGroup.get(use: eventsHandler)
        openAuthGroup.get("match", String.parameter, use: eventsMatchHandler)
        openAuthGroup.get("now", use: eventsNowHandler)
        openAuthGroup.get("official", use: officialHandler)
        openAuthGroup.get("official", "now", use: officialNowHandler)
        openAuthGroup.get("official", "today", use: officialTodayHandler)
        openAuthGroup.get("shadow", use: shadowHandler)
        openAuthGroup.get("shadow", "now", use: shadowNowHandler)
        openAuthGroup.get("shadow", "today", use: shadowTodayHandler)
        openAuthGroup.get("today", use: eventsTodayHandler)

        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get(Event.parameter, "forum", use: eventForumHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.post(Event.parameter, "favorite", use: favoriteAddHandler)
        tokenAuthGroup.post(Event.parameter, "favorite", "remove", use: favoriteRemoveHandler)
        tokenAuthGroup.get("favorites", use: favoritesHandler)
        tokenAuthGroup.post(EventsUpdateData.self, at: "update", use: eventsUpdateHandler)
    }
    
    // MARK: - Open Access Handlers
    // The handlers in this route group do not require Authorization, but can take advantage
    // of Authorization headers if they are present.

    /// `GET /api/v3/events`
    ///
    /// Retrieve entire event schedule.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all events.
    func eventsHandler(_ req: Request) throws -> Future<[EventData]> {
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/match/STRING`
    ///
    /// Retrieve all events whose title or description contain the specfied string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all matching events.
    func eventsMatchHandler(_ req: Request) throws -> Future<[EventData]> {
        var search = try req.parameters.next(String.self)
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req).group(.or) {
                (or) in
                or.filter(\.title, .ilike, "%\(search)%")
                or.filter(\.info, .ilike, "%\(search)%")
            }.all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req).group(.or) {
                (or) in
                or.filter(\.title, .ilike, "%\(search)%")
                or.filter(\.info, .ilike, "%\(search)%")
            }.all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/now`
    ///
    /// Retrieve all events happening now.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all current events.
    func eventsNowHandler(_ req: Request) throws -> Future<[EventData]> {
        let now = Date()
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.startTime <= now)
                .filter(\.endTime > now)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.startTime <= now)
                .filter(\.endTime > now)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/today`
    ///
    /// Retrieve all events for the current day.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all events for the current day.
    func eventsTodayHandler(_ req: Request) throws -> Future<[EventData]> {
        // FIXME: is this handling UTC correctly?
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Date.init(timeInterval: 86400, since: todayStart)
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.startTime >= todayStart)
                .filter(\.startTime < todayEnd)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.startTime >= todayStart)
                .filter(\.startTime < todayEnd)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/official`
    ///
    /// Retrieve all official events on the schedule.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all official events.
    func officialHandler(_ req: Request) throws -> Future<[EventData]> {
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.eventType != .shadow)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.eventType != .shadow)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/official/now`
    ///
    /// Retrieve all official events happening now.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all current official events.
    func officialNowHandler(_ req: Request) throws -> Future<[EventData]> {
        let now = Date()
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.eventType != .shadow)
                .filter(\.startTime <= now)
                .filter(\.endTime > now)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.eventType != .shadow)
                .filter(\.startTime <= now)
                .filter(\.endTime > now)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/official/today`
    ///
    /// Retrieve all official events for the current day.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all official events for the current day.
    func officialTodayHandler(_ req: Request) throws -> Future<[EventData]> {
        // FIXME: is this handling UTC correctly?
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Date.init(timeInterval: 86400, since: todayStart)
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.eventType != .shadow)
                .filter(\.startTime >= todayStart)
                .filter(\.startTime < todayEnd)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.eventType != .shadow)
                .filter(\.startTime >= todayStart)
                .filter(\.startTime < todayEnd)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/shadow`
    ///
    /// Retrieve all shadow events on the schedule.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all shadow events.
    func shadowHandler(_ req: Request) throws -> Future<[EventData]> {
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.eventType == .shadow)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.eventType == .shadow)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/shadow/now`
    ///
    /// Retrieve all shadow events happening now.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all current shadow events.
    func shadowNowHandler(_ req: Request) throws -> Future<[EventData]> {
        let now = Date()
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.eventType == .shadow)
                .filter(\.startTime <= now)
                .filter(\.endTime > now)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.eventType == .shadow)
                .filter(\.startTime <= now)
                .filter(\.endTime > now)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/events/shadow/today`
    ///
    /// Retrieve all shadow events for the current day.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all shadow events for the current day.
    func shadowTodayHandler(_ req: Request) throws -> Future<[EventData]> {
        // FIXME: is this handling UTC correctly?
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Date.init(timeInterval: 86400, since: todayStart)
        // check if we have a user
        let auth = try req.authenticated(User.self)
        guard let user = auth else {
            // return untagged events if not
            return Event.query(on: req)
                .filter(\.eventType == .shadow)
                .filter(\.startTime >= todayStart)
                .filter(\.startTime < todayEnd)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: false) }
            }
        }
        // else tag events
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            let uuids = barrel?.modelUUIDs ?? []
            return Event.query(on: req)
                .filter(\.eventType == .shadow)
                .filter(\.startTime >= todayStart)
                .filter(\.startTime < todayEnd)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map {
                        (event) in
                        if uuids.contains(try event.requireID()) {
                            return try event.convertToData(withFavorited: true)
                        } else {
                            return try event.convertToData(withFavorited: false)
                        }
                    }
            }
        }
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/events/ID/forum`
    ///
    /// Retrieve the `Forum` associated with an `Event`, with all its `ForumPost`s. Content from
    /// blocked or muted users, or containing user's muteWords, is not returned.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `ForumData` containing the forum's metadata and all posts.
    func eventForumHandler(_ req: Request) throws -> Future<ForumData> {
        let user = try req.requireAuthenticated(User.self)
        // get event
        return try req.parameters.next(Event.self).flatMap {
            (event) in
            // get forum
            guard let forumID = event.forumID else {
                throw Abort(.internalServerError, reason: "event has no forum")
            }
            return Forum.find(forumID, on: req)
                .unwrap(or: Abort(.internalServerError, reason: "forum not found"))
                .flatMap {
                    (forum) in
                    // filter posts
                    return try self.getCachedFilters(for: user, on: req).flatMap {
                        (tuple) in
                        let blocked = tuple.0
                        let muted = tuple.1
                        let mutewords = tuple.2
                        return try forum.posts.query(on: req)
                            .filter(\.authorID !~ blocked)
                            .filter(\.authorID !~ muted)
                            .sort(\.createdAt, .ascending)
                            .all()
                            .flatMap {
                                (posts) in
                                // remove muteword posts
                                let filteredPosts = posts.compactMap {
                                    self.filterMutewords(for: $0, using: mutewords, on: req)
                                }
                                // convert to PostData
                                let postsData = try filteredPosts.map {
                                    (filteredPost) -> Future<PostData> in
                                    let userLike = try PostLikes.query(on: req)
                                        .filter(\.postID == filteredPost.requireID())
                                        .filter(\.userID == user.requireID())
                                        .first()
                                    let likeCount = try PostLikes.query(on: req)
                                        .filter(\.postID == filteredPost.requireID())
                                        .count()
                                    return map(userLike, likeCount) {
                                        (resolvedLike, count) in
                                        return try filteredPost.convertToData(
                                            withLike: resolvedLike?.likeType,
                                            likeCount: count
                                        )
                                    }
                                }
                                return postsData.flatten(on: req).map {
                                    (flattenedPosts) in
                                    return try ForumData(
                                        forumID: forum.requireID(),
                                        title: forum.title,
                                        creatorID: forum.creatorID,
                                        isLocked: forum.isLocked,
                                        posts: flattenedPosts
                                    )
                                }
                        }
                    }
            }
        }
    }
    
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
    func eventsUpdateHandler(_ req: Request, data: EventsUpdateData) throws -> Future<[EventData]> {
        let user = try req.requireAuthenticated(User.self)
        guard user.accessLevel == .admin else {
            throw Abort(.forbidden, reason: "admins only")
        }
        var schedule = data.schedule
        schedule = schedule.replacingOccurrences(of: "&amp;", with: "&")
        schedule = schedule.replacingOccurrences(of: "\\,", with: ",")
        let psqlConnection = req.newConnection(to: .psql)
        return psqlConnection.flatMap {
            (connection) in
            // convert to [Event]
            let scheduleArray = schedule.components(separatedBy: .newlines)
            let scheduleEvents = EventParser().parse(scheduleArray, on: connection)
            let existingEvents = Event.query(on: req).all()
            return flatMap(scheduleEvents, existingEvents) {
                (updates, events) in
                var updatedEvents: [Future<Event>] = []
                for update in updates {
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
                            updatedEvents.append(event.save(on: req))
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
                        updatedEvents.append(newEvent.save(on: req))
                    }
                }
                // resolve futures, return as EventData
                return updatedEvents.flatten(on: req).map {
                    (returnEvents) in
                    return try returnEvents.map { try $0.convertToData(withFavorited: false) }
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
    func favoriteAddHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // get event
        return try req.parameters.next(Event.self).flatMap {
            (event) in
            // get user's taggedEvent barrel
            return try Barrel.query(on: req)
                .filter(\.ownerID == user.requireID())
                .filter(\.barrelType == .taggedEvent)
                .first()
                .flatMap {
                    (eventBarrel) in
                    // create barrel if needed
                    let barrel = try eventBarrel ?? Barrel(
                        ownerID: user.requireID(),
                        barrelType: .taggedEvent
                    )
                    // add event and return 201
                    barrel.modelUUIDs.append(try event.requireID())
                    return barrel.save(on: req).transform(to: .created)
                }
        }
    }
    
    /// `POST /api/v3/events/ID/favorite/remove`
    ///
    /// Remove the specified `Event` from the user's tagged events list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the event was not favorited.
    /// - Returns: 204 No Content on success.
    func favoriteRemoveHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // get event
        return try req.parameters.next(Event.self).flatMap {
            (event) in
            // get user's taggedEvent barrel
            return try Barrel.query(on: req)
                .filter(\.ownerID == user.requireID())
                .filter(\.barrelType == .taggedEvent)
                .first()
                .flatMap {
                    (eventBarrel) in
                    guard let barrel = eventBarrel else {
                        throw Abort(.badRequest, reason: "user has not tagged any events")
                    }
                    // remove event
                    guard let index = barrel.modelUUIDs.firstIndex(of: try event.requireID()) else {
                        throw Abort(.badRequest, reason: "event was not tagged")
                    }
                    barrel.modelUUIDs.remove(at: index)
                    return barrel.save(on: req).transform(to: .noContent)
            }
        }
    }
    
    /// `GET /api/v3/events/favorites`
    ///
    /// Retrieve the `Event`s in the user's taggedEvent barrel, sorted by `.startTime`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing the user's favorited events.
    func favoritesHandler(_ req: Request) throws -> Future<[EventData]> {
        let user = try req.requireAuthenticated(User.self)
        // get user's taggedEvent barrel
        return try self.getTaggedBarrel(for: user, on: req).flatMap {
            (barrel) in
            guard let barrel = barrel else {
                // return empty array
                return req.future([EventData]())
            }
            // get events
            return Event.query(on: req)
                .filter(\.id ~~ barrel.modelUUIDs)
                .sort(\.startTime, .ascending)
                .all()
                .map {
                    (events) in
                    return try events.map { try $0.convertToData(withFavorited: true) }
            }
        }
    }
}
