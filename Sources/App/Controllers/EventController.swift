import Vapor
import Crypto
import FluentSQL

struct EventController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let eventRoutes = router.grouped("api", "v3", "events")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let tokenAuthGroup = eventRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        eventRoutes.get(use: eventsHandler)
        eventRoutes.get("match", String.parameter, use: eventsMatchHandler)
        eventRoutes.get("now", use: eventsNowHandler)
        eventRoutes.get("official", use: officialHandler)
        eventRoutes.get("official", "now", use: officialNowHandler)
        eventRoutes.get("official", "today", use: officialTodayHandler)
        eventRoutes.get("shadow", use: shadowHandler)
        eventRoutes.get("shadow", "now", use: shadowNowHandler)
        eventRoutes.get("shadow", "today", use: shadowTodayHandler)
        eventRoutes.get("today", use: eventsTodayHandler)
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        
        // endpoints available only when logged in
        
    }
    
    // MARK: - Open Access Handlers
    
    /// `GET /api/v3/events`
    ///
    /// Retrieve entire event schedule.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all events.
    func eventsHandler(_ req: Request) throws -> Future<[EventData]> {
        return Event.query(on: req)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
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
        return Event.query(on: req).group(.or) {
            (or) in
            or.filter(\.title, .ilike, "%\(search)%")
            or.filter(\.description, .ilike, "%\(search)%")
        }.all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
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
        return Event.query(on: req)
            .filter(\.startTime <= now)
            .filter(\.endTime > now)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
        }
    }
    
    /// `GET /api/v3/events/today`
    ///
    /// Retrieve all events for the current day.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all events for the current day.
    func eventsTodayHandler(_ req: Request) throws -> Future<[EventData]> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = Date.init(timeInterval: 86400, since: todayStart)
        return Event.query(on: req)
            .filter(\.startTime >= todayStart)
            .filter(\.startTime < todayEnd)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
        }
    }
    /// `GET /api/v3/events/official`
    ///
    /// Retrieve all official events on the schedule.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all official events.
    func officialHandler(_ req: Request) throws -> Future<[EventData]> {
        return Event.query(on: req)
            .filter(\.eventType != .shadow)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
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
        return Event.query(on: req)
            .filter(\.eventType != .shadow)
            .filter(\.startTime <= now)
            .filter(\.endTime > now)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
        }
    }
    
    /// `GET /api/v3/events/official/today`
    ///
    /// Retrieve all official events for the current day.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all official events for the current day.
    func officialTodayHandler(_ req: Request) throws -> Future<[EventData]> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = Date.init(timeInterval: 86400, since: todayStart)
        return Event.query(on: req)
            .filter(\.eventType != .shadow)
            .filter(\.startTime >= todayStart)
            .filter(\.startTime < todayEnd)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
        }
    }
    
    /// `GET /api/v3/events/shadow`
    ///
    /// Retrieve all shadow events on the schedule.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all shadow events.
    func shadowHandler(_ req: Request) throws -> Future<[EventData]> {
        return Event.query(on: req)
            .filter(\.eventType == .shadow)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
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
        return Event.query(on: req)
            .filter(\.eventType == .shadow)
            .filter(\.startTime <= now)
            .filter(\.endTime > now)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
        }
    }
    
    /// `GET /api/v3/events/shadow/today`
    ///
    /// Retrieve all shadow events for the current day.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[EventData]` containing all shadow events for the current day.
    func shadowTodayHandler(_ req: Request) throws -> Future<[EventData]> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = Date.init(timeInterval: 86400, since: todayStart)
        return Event.query(on: req)
            .filter(\.eventType == .shadow)
            .filter(\.startTime >= todayStart)
            .filter(\.startTime < todayEnd)
            .sort(\.startTime, .ascending)
            .all()
            .map {
                (events) in
                return try events.map { try $0.convertToData() }
        }
    }
    
}
