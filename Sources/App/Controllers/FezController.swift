import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of /api/v3/fez/* route endpoints and handler functions related
/// to FriendlyFez/LFG barrels.

struct FezController: RouteCollection {
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/fez endpoints
        let fezRoutes = router.grouped("api", "v3", "fez")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let sharedAuthGroup = fezRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = fezRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        sharedAuthGroup.get("types", use: typesHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.post(FezCreateData.self, at: "create", use: createHandler)
        tokenAuthGroup.post(Barrel.parameter, "join", use: joinHandler)
        tokenAuthGroup.get("joined", use: joinedHandler)
        tokenAuthGroup.post(Barrel.parameter, "unjoin", use: unjoinHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `/GET /api/v3/fez/types`
    ///
    /// Retrieve a list of all values for `FezType` as strings.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[String]` containing the `.label` value for each type.
    func typesHandler(_ req: Request) throws -> Future<[String]> {
        return req.future(FezType.allCases.map { $0.label })
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/fez/create`
    ///
    /// Create a `Barrel` of `BarrelType` `.friendlyFez`. The creating user is automatically
    /// added to the participant list.
    ///
    /// The list of recognized values for use in the `.fezType` field is obtained from
    /// `GET /api/v3/fez/types`.
    ///
    /// The `.startTime` and `.endTime` fields should be passed as string representations of a
    /// date. The representation must be either a string literal of seconds since epoch (e.g.
    /// "1574364635") or an ISO8601 string. To create an open-ended / unknown `.startTime` or
    /// `.endTime` for the FriendlyFez, pass an *empty* string `""` as the value. This will be
    /// converted to "TBD" for display.
    ///
    /// - Important: Do **not** pass "0" as the date value. Unless you really are scheduling
    ///   something for the first stroke of midnight in 1970.
    ///
    /// A value of 0 in either the `.minCapacity` or `.maxCapacity` fields indicates an undefined
    /// limit: "there is no minimum", "there is no maximum".
    ///
    /// - Requires: `FezCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `FezCreateData` containing the fez data.
    /// - Throws: 400 error if the supplied data does not validate.
    /// - Returns: `FezData` containing the newly created fez.
    func createHandler(_ req: Request, data: FezCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // see `FezCreateData.validations()`
        try data.validate()
        // create barrel
        let barrel = try Barrel(
            ownerID: user.requireID(),
            barrelType: .friendlyFez,
            name: data.title,
            modelUUIDs: [user.requireID()],
            userInfo: [
                "label": [data.fezType],
                "info": [data.info],
                "startTime": [data.startTime],
                "endTime": [data.endTime],
                "location": [data.location],
                "minCapacity": [String(data.minCapacity)],
                "maxCapacity": [String(data.maxCapacity)],
                "waitList": []
            ]
        )
        return barrel.save(on: req).map {
            (savedBarrel) in
            // return as FezData
            var fezData = try FezData(
                fezID: savedBarrel.requireID(),
                ownerID: user.requireID(),
                fezType: data.fezType,
                title: data.title,
                info: data.info,
                startTime: self.fezTimeString(from: data.startTime),
                endTime: self.fezTimeString(from: data.endTime),
                location: data.location,
                seamonkeys: [user.convertToSeaMonkey()],
                waitingList: []
            )
            // add empty slot fezzes
            if data.maxCapacity > 0 {
                while fezData.seamonkeys.count < data.maxCapacity {
                    let fezMonkey = SeaMonkey(
                        userID: Settings.shared.friendlyFezID,
                        username: "AvailableSlot"
                    )
                    fezData.seamonkeys.append(fezMonkey)
                }
            }
            // with 201 status
            let response = Response(http: HTTPResponse(status: .created), using: req)
            try response.content.encode(fezData)
            return response
        }
    }
    
    /// `POST /api/v3/fez/ID/join`
    ///
    /// Add the current user to the `FriendlyFez`. If the `.maxCapacity` of the fez has been
    /// reached, the user is added to the waiting list.
    ///
    /// - Note: A user cannot join a fez that is owned by a blocked or blocking user. If any
    ///   current participating or waitList user is in the user's blocks, their identity is
    ///   replaced by a placeholder in the returned data. It is the user's responsibility to
    ///   examine the participant list for conflicts prior to joining or attending.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the supplied ID is not a fez barrel or user is already in fez.
    ///   404 error if a block between the user and fez owner applies. A 5xx response should be
    ///   reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez data.
    func joinHandler(_ req: Request) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            // respect blocks
            let cache = try req.keyedCache(for: .redis)
            let key = try "blocks:\(user.requireID())"
            let blocks = cache.get(key, as: [UUID].self)
            return blocks.flatMap {
                (blocks) in
                let blocked = blocks ?? []
                guard !blocked.contains(barrel.ownerID) else {
                    throw Abort(.notFound, reason: "fez barrel is not available")
                }
                // ensure we have a capacity value
                guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                    let maxMonkeys = Int(maxString) else {
                        throw Abort(.internalServerError, reason: "maxCapacity not found")
                }
                // add user
                try barrel.modelUUIDs.append(user.requireID())
                return barrel.save(on: req).flatMap {
                    (savedBarrel) in
                    // return as FezData
                    var fezData = try FezData(
                        fezID: savedBarrel.requireID(),
                        ownerID: savedBarrel.ownerID,
                        fezType: savedBarrel.userInfo["fezType"]?[0] ?? "",
                        title: savedBarrel.name,
                        info: savedBarrel.userInfo["info"]?[0] ?? "",
                        startTime: self.fezTimeString(from: savedBarrel.userInfo["startTime"]?[0] ?? ""),
                        endTime: self.fezTimeString(from: savedBarrel.userInfo["endTime"]?[0] ?? ""),
                        location: savedBarrel.userInfo["location"]?[0] ?? "",
                        seamonkeys: [],
                        waitingList: []
                    )
                    // convert UUIDs to users
                    var futureSeamonkeys = [Future<User?>]()
                    for uuid in barrel.modelUUIDs {
                        futureSeamonkeys.append(User.find(uuid, on: req))
                    }
                    // resolve futures
                    return futureSeamonkeys.flatten(on: req).map {
                        (seamonkeys) in
                        // convert valid users to seamonkeys
                        let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
                        // masquerade blocked users
                        for (index, seamonkey) in valids.enumerated() {
                            if blocked.contains(seamonkey.userID) {
                                let blockedMonkey = SeaMonkey(
                                    userID: Settings.shared.blockedUserID,
                                    username: "BlockedUser"
                                )
                                fezData.seamonkeys.remove(at: index)
                                fezData.seamonkeys.insert(blockedMonkey, at: index)
                            }
                        }
                        // populate fezData
                        switch (valids.count, maxMonkeys)  {
                            // unlimited slots
                            case (_, let max) where max == 0:
                                fezData.seamonkeys = valids
                            // open slots
                            case (let count, let max) where count < max:
                                fezData.seamonkeys = valids
                                // add empty slot fezzes
                                while fezData.seamonkeys.count < max {
                                    let fezMonkey = SeaMonkey(
                                        userID: Settings.shared.friendlyFezID,
                                        username: "AvailableSlot"
                                    )
                                    fezData.seamonkeys.append(fezMonkey)
                            }
                            // full + waiting list
                            case (let count, let max) where count > max:
                                fezData.seamonkeys = Array(valids[valids.startIndex..<max])
                                fezData.waitingList = Array(valids[max..<valids.endIndex])
                            // exactly full
                            default:
                                fezData.seamonkeys = valids
                        }
                        // return with 201 status
                        let response = Response(http: HTTPResponse(status: .created), using: req)
                        try response.content.encode(fezData)
                        return response
                    }
                }
            }
        }
    }
    
    /// `GET /api/v3/fez/joined`
    ///
    /// Retrieve all the FriendlyFez barrels that the user has joined.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `[FezData]` containing all the fezzes joined by the user.
    func joinedHandler(_ req: Request) throws -> Future<[FezData]> {
        let user = try req.requireAuthenticated(User.self)
        // get fez barrels
        return Barrel.query(on: req)
            .filter(\.barrelType == .friendlyFez)
            .all()
            .flatMap {
                (barrels) in
                // get blocks to respect later
                let cache = try req.keyedCache(for: .redis)
                let key = try "blocks:\(user.requireID())"
                let blocks = cache.get(key, as: [UUID].self)
                return blocks.flatMap {
                    (blocks) in
                    let blocked = blocks ?? []
                    // get user's barrels
                    var userBarrels = [Barrel]()
                    for barrel in barrels {
                        if barrel.modelUUIDs.contains(try user.requireID()) {
                            userBarrels.append(barrel)
                        }
                    }
                    // convert to FezData
                    let fezzesData = try userBarrels.map {
                        (barrel) -> Future<FezData> in
                        // ensure we have a capacity value
                        guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                            let maxMonkeys = Int(maxString) else {
                                throw Abort(.internalServerError, reason: "maxCapacity not found")
                        }
                        // init return struct
                        var fezData = try FezData(
                            fezID: barrel.requireID(),
                            ownerID: barrel.ownerID,
                            fezType: barrel.userInfo["fezType"]?[0] ?? "",
                            title: barrel.name,
                            info: barrel.userInfo["info"]?[0] ?? "",
                            startTime: self.fezTimeString(from: barrel.userInfo["startTime"]?[0] ?? ""),
                            endTime: self.fezTimeString(from: barrel.userInfo["endTime"]?[0] ?? ""),
                            location: barrel.userInfo["location"]?[0] ?? "",
                            seamonkeys: [],
                            waitingList: []
                        )
                        // convert UUIDs to users
                        var futureSeamonkeys = [Future<User?>]()
                        for uuid in barrel.modelUUIDs {
                            futureSeamonkeys.append(User.find(uuid, on: req))
                        }
                        // resolve futures
                        return futureSeamonkeys.flatten(on: req).map {
                            (seamonkeys) in
                            // convert valid users to seamonkeys
                            let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
                            // masquerade blocked users
                            for (index, seamonkey) in valids.enumerated() {
                                if blocked.contains(seamonkey.userID) {
                                    let blockedMonkey = SeaMonkey(
                                        userID: Settings.shared.blockedUserID,
                                        username: "BlockedUser"
                                    )
                                    fezData.seamonkeys.remove(at: index)
                                    fezData.seamonkeys.insert(blockedMonkey, at: index)
                                }
                            }
                            // populate fezData
                            switch (valids.count, maxMonkeys)  {
                                // unlimited slots
                                case (_, let max) where max == 0:
                                    fezData.seamonkeys = valids
                                // open slots
                                case (let count, let max) where count < max:
                                    fezData.seamonkeys = valids
                                    // add empty slot fezzes
                                    while fezData.seamonkeys.count < max {
                                        let fezMonkey = SeaMonkey(
                                            userID: Settings.shared.friendlyFezID,
                                            username: "AvailableSlot"
                                        )
                                        fezData.seamonkeys.append(fezMonkey)
                                }
                                // full + waiting list
                                case (let count, let max) where count > max:
                                    fezData.seamonkeys = Array(valids[valids.startIndex..<max])
                                    fezData.waitingList = Array(valids[max..<valids.endIndex])
                                // exactly full
                                default:
                                    fezData.seamonkeys = valids
                            }
                            return fezData
                        }
                    }
                    return fezzesData.flatten(on: req)
                }
        }
    }
    
    /// `POST /api/v3/fez/ID/unjoin`
    ///
    /// Remove the current user from the `FriendlyFez`. If the `.maxCapacity` of the fez had
    /// previously been reached, the first user from the waiting list, if any, is moved to the
    /// participant list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the supplied ID is not a fez barrel. A 5xx response should be
    ///   reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez data.
    func unjoinHandler(_ req: Request) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            // get blocks to respect later
            let cache = try req.keyedCache(for: .redis)
            let key = try "blocks:\(user.requireID())"
            let blocks = cache.get(key, as: [UUID].self)
            return blocks.flatMap {
                (blocks) in
                let blocked = blocks ?? []
                // ensure we have a capacity value
                guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                    let maxMonkeys = Int(maxString) else {
                        throw Abort(.internalServerError, reason: "maxCapacity not found")
                }
                // remove user
                if let index = barrel.modelUUIDs.firstIndex(of: try user.requireID()) {
                    barrel.modelUUIDs.remove(at: index)
                }
                return barrel.save(on: req).flatMap {
                    (savedBarrel) in
                    // return as FezData
                    var fezData = try FezData(
                        fezID: savedBarrel.requireID(),
                        ownerID: savedBarrel.ownerID,
                        fezType: savedBarrel.userInfo["fezType"]?[0] ?? "",
                        title: savedBarrel.name,
                        info: savedBarrel.userInfo["info"]?[0] ?? "",
                        startTime: self.fezTimeString(from: savedBarrel.userInfo["startTime"]?[0] ?? ""),
                        endTime: self.fezTimeString(from: savedBarrel.userInfo["endTime"]?[0] ?? ""),
                        location: savedBarrel.userInfo["location"]?[0] ?? "",
                        seamonkeys: [],
                        waitingList: []
                    )
                    // convert UUIDs to users
                    var futureSeamonkeys = [Future<User?>]()
                    for uuid in barrel.modelUUIDs {
                        futureSeamonkeys.append(User.find(uuid, on: req))
                    }
                    // resolve futures
                    return futureSeamonkeys.flatten(on: req).map {
                        (seamonkeys) in
                        // convert valid users to seamonkeys
                        let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
                        // masquerade blocked users
                        for (index, seamonkey) in valids.enumerated() {
                            if blocked.contains(seamonkey.userID) {
                                let blockedMonkey = SeaMonkey(
                                    userID: Settings.shared.blockedUserID,
                                    username: "BlockedUser"
                                )
                                fezData.seamonkeys.remove(at: index)
                                fezData.seamonkeys.insert(blockedMonkey, at: index)
                            }
                        }
                        // populate fezData
                        switch (valids.count, maxMonkeys)  {
                            // unlimited slots
                            case (_, let max) where max == 0:
                                fezData.seamonkeys = valids
                            // open slots
                            case (let count, let max) where count < max:
                                fezData.seamonkeys = valids
                                // add empty slot fezzes
                                while fezData.seamonkeys.count < max {
                                    let fezMonkey = SeaMonkey(
                                        userID: Settings.shared.friendlyFezID,
                                        username: "AvailableSlot"
                                    )
                                    fezData.seamonkeys.append(fezMonkey)
                            }
                            // full + waiting list
                            case (let count, let max) where count > max:
                                fezData.seamonkeys = Array(valids[valids.startIndex..<max])
                                fezData.waitingList = Array(valids[max..<valids.endIndex])
                            // exactly full
                            default:
                                fezData.seamonkeys = valids
                        }
                        // return with 204 status
                        let response = Response(http: HTTPResponse(status: .noContent), using: req)
                        try response.content.encode(fezData)
                        return response
                    }
                }
            }
        }
    }
}

// MARK: - Helper Functions

extension FezController {
    /// Returns a display string representation of a date stored as a string in either ISO8601
    /// format or as a literal Double.
    ///
    /// - Parameter string: The string representation of the date.
    /// - Returns: String in date format "E, H:mm a", or "TBD" if the string value is "0" or
    ///   the date string is invalid.
    func fezTimeString(from string: String) -> String {
        let dateFormtter = DateFormatter()
        dateFormtter.dateFormat = "E, h:mm a"
        dateFormtter.timeZone = TimeZone(secondsFromGMT: 0)
        switch string {
            case "0":
                return "TBD"
            default:
                if let date = FezController.dateFromParameter(string: string) {
                    return dateFormtter.string(from: date)
                } else {
                    return "TBD"
            }
        }
    }
}
