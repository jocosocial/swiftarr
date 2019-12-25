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
        sharedAuthGroup.get("joined", use: joinedHandler)
        sharedAuthGroup.get("open", use: openHandler)
        sharedAuthGroup.get("types", use: typesHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.get(Barrel.parameter, use: fezHandler)
        tokenAuthGroup.post(Barrel.parameter, "cancel", use: cancelHandler)
        tokenAuthGroup.post(FezContentData.self, at: "create", use: createHandler)
        tokenAuthGroup.post(Barrel.parameter, "join", use: joinHandler)
        tokenAuthGroup.get("owner", use: ownerHandler)
        tokenAuthGroup.post(PostCreateData.self, at: Barrel.parameter, "post", use: postAddHandler)
        tokenAuthGroup.post("post", FezPost.parameter, "delete", use: postDeleteHandler)
        tokenAuthGroup.post(Barrel.parameter, "unjoin", use: unjoinHandler)
        tokenAuthGroup.post(FezContentData.self, at: Barrel.parameter, "update", use: updateHandler)
        tokenAuthGroup.post(Barrel.parameter, "user", User.parameter, "add", use: userAddHandler)
        tokenAuthGroup.post(Barrel.parameter, "user", User.parameter, "remove", use: userRemoveHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
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
    
    /// `GET /api/v3/fez/open`
    ///
    /// Retrieve all FriendlyFez barrels with open slots and a startTime of no earlier than
    /// one hour ago.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `[FezData]` containing all current fezzes with open slots.
    func openHandler(_ req: Request) throws -> Future<[FezData]> {
        let user = try req.requireAuthenticated(User.self)
        // respect blocks
        let cache = try req.keyedCache(for: .redis)
        let key = try "blocks:\(user.requireID())"
        let blocks = cache.get(key, as: [UUID].self)
        return blocks.flatMap {
            (blocks) in
            let blocked = blocks ?? []
            // get fez barrels
            return Barrel.query(on: req)
                .filter(\.barrelType == .friendlyFez)
                .filter(\.ownerID !~ blocked)
                .all()
                .flatMap {
                    (barrels) in
                    // get open barrels
                    var openBarrels = [Barrel]()
                    for barrel in barrels {
                        let currentCount = barrel.modelUUIDs.count
                        let maxCount = Int(barrel.userInfo["maxCapacity"]?[0] ?? "0") ?? 0
                        let startTime = FezController.dateFromParameter(
                            string: barrel.userInfo["startTime"]?[0] ?? "") ?? Date()
                        // if open slots and started no more than 1 hour ago
                        if (currentCount < maxCount || maxCount == 0)
                            && startTime > Date().addingTimeInterval(-3600) {
                            openBarrels.append(barrel)
                        }
                    }
                    // convert to FezData
                    let fezzesData = try openBarrels.map {
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
    
    /// `POST /api/v3/fez/ID/cancel`
    ///
    /// Cancel a FriendlyFez.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is not the fez owner. A 5xx response should be
    ///   reported as a likely bug, please and thank you.
    /// - Returns: `FezData` with the updated fez info.
    func cancelHandler(_ req: Request) throws -> Future<FezData> {
        let user = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            guard try barrel.ownerID == user.requireID() else {
                throw Abort(.forbidden, reason: "user does not own fez")
            }
            // FIXME: this should send out notifications
            // return as  FezData
            var fezData = try FezData(
                fezID: barrel.requireID(),
                ownerID: barrel.ownerID,
                fezType: barrel.userInfo["fezType"]?[0] ?? "",
                title: "[CANCELLED] " + barrel.name,
                info: "[CANCELLED] " + (barrel.userInfo["info"]?[0] ?? ""),
                startTime: "[CANCELLED]",
                endTime: "[CANCELLED]",
                location: "[CANCELLED] " + (barrel.userInfo["location"]?[0] ?? ""),
                seamonkeys: [],
                waitingList: []
            )
            // ensure we have a capacity value
            guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                let maxMonkeys = Int(maxString) else {
                    throw Abort(.internalServerError, reason: "maxCapacity not found")
            }
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
    }
    
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
    /// - Requires: `FezContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `FezContentData` containing the fez data.
    /// - Throws: 400 error if the supplied data does not validate.
    /// - Returns: `FezData` containing the newly created fez.
    func createHandler(_ req: Request, data: FezContentData) throws -> Future<Response> {
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
    
    /// `GET /api/v3/fez/ID`
    ///
    /// Retrieve the specified FriendlyFez with all fez discussion `FezPost`s.
    ///
    /// - Note: Posts are subject to block and mute user filtering, but mutewords are ignored
    ///   in order to not suppress potentially important information.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if a block between the user and fez owner applies. A 5xx response
    ///   should be reported as a likely bug, please and thank you.
    /// - Returns: `FezDetailData` with fez info and all discussion posts.
    func fezHandler(_ req: Request) throws -> Future<FezDetailData> {
        let user = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            // get blocks
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                guard !blocked.contains(barrel.ownerID) else {
                    throw Abort(.notFound, reason: "fez barrel is not available")
                }
                // ensure we have a capacity value
                guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                    let maxMonkeys = Int(maxString) else {
                        throw Abort(.internalServerError, reason: "maxCapacity not found")
                }
                // return as FezDetailData
                var fezDetailData = try FezDetailData(
                    fezID: barrel.requireID(),
                    ownerID: barrel.ownerID,
                    fezType: barrel.userInfo["fezType"]?[0] ?? "",
                    title: barrel.name,
                    info: barrel.userInfo["info"]?[0] ?? "",
                    startTime: self.fezTimeString(from: barrel.userInfo["startTime"]?[0] ?? ""),
                    endTime: self.fezTimeString(from: barrel.userInfo["endTime"]?[0] ?? ""),
                    location: barrel.userInfo["location"]?[0] ?? "",
                    seamonkeys: [],
                    waitingList: [],
                    posts: []
                )
                // convert UUIDs to users
                var futureSeamonkeys = [Future<User?>]()
                for uuid in barrel.modelUUIDs {
                    futureSeamonkeys.append(User.find(uuid, on: req))
                }
                // resolve futures
                return futureSeamonkeys.flatten(on: req).flatMap {
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
                            fezDetailData.seamonkeys.remove(at: index)
                            fezDetailData.seamonkeys.insert(blockedMonkey, at: index)
                        }
                    }
                    // populate fezDetailData
                    switch (valids.count, maxMonkeys)  {
                        // unlimited slots
                        case (_, let max) where max == 0:
                            fezDetailData.seamonkeys = valids
                        // open slots
                        case (let count, let max) where count < max:
                            fezDetailData.seamonkeys = valids
                            // add empty slot fezzes
                            while fezDetailData.seamonkeys.count < max {
                                let fezMonkey = SeaMonkey(
                                    userID: Settings.shared.friendlyFezID,
                                    username: "AvailableSlot"
                                )
                                fezDetailData.seamonkeys.append(fezMonkey)
                        }
                        // full + waiting list
                        case (let count, let max) where count > max:
                            fezDetailData.seamonkeys = Array(valids[valids.startIndex..<max])
                            fezDetailData.waitingList = Array(valids[max..<valids.endIndex])
                        // exactly full
                        default:
                            fezDetailData.seamonkeys = valids
                    }
                    // get posts
                    return try FezPost.query(on: req)
                        .filter(\.fezID == barrel.requireID())
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .sort(\.createdAt, .ascending)
                        .all()
                        .map {
                            (posts) in
                            // add as FezPostData
                            fezDetailData.posts = try posts.map { try $0.convertToData() }
                            return fezDetailData
                    }
                }
            }
        }
    }
    
    /// `POST /api/v3/fez/ID/join`
    ///
    /// Add the current user to the FriendlyFez. If the `.maxCapacity` of the fez has been
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
    
    /// `GET /api/v3/fez/owner`
    ///
    /// Retrieve the FriendlyFez barrels created by the user.
    ///
    /// - Note: There is no block filtering on this endpoint. In theory, a block could only
    ///   apply if it were set *after* the fez had been joined by the second party. The
    ///   owner of the fez has the ability to remove users if desired, and the fez itself is no
    ///   longer visible to the non-owning party.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `[FezData]` containing all the fezzes created by the user.
    func ownerHandler(_ req: Request) throws -> Future<[FezData]> {
        let user = try req.requireAuthenticated(User.self)
        // get owned fez barrels
        return try Barrel.query(on: req)
            .filter(\.ownerID == user.requireID())
            .filter(\.barrelType == .friendlyFez)
            .all()
            .flatMap {
                (barrels) in
                // convert to FezData
                let fezzesData = try barrels.map {
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
    
    /// `POST /api/v3/fez/ID/post`
    ///
    /// Add a `FezPost` to the specified FriendlyFez `Barrel`.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically
    ///   - data: `PostCreateData` containing the post's contents and optional image.
    /// - Throws: 404 error if the fez is not available. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: `FezDetailData` containing the updated fez discussion.
    func postAddHandler(_ req: Request, data: PostCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // see PostContentData.validations()
        try data.validate()
        // get fez
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            // process image
            return try self.processImage(data: data.imageData, forType: .forumPost, on: req).flatMap {
                (filename) in
                // create post
                let post = try FezPost(
                    fezID: barrel.requireID(),
                    authorID: user.requireID(),
                    text: data.text,
                    image: filename
                )
                return post.save(on: req).flatMap {
                    (_) in
                    // get blocks
                    return try self.getCachedFilters(for: user, on: req).flatMap {
                        (tuple) in
                        let blocked = tuple.0
                        let muted = tuple.1
                        guard !blocked.contains(barrel.ownerID) else {
                            throw Abort(.notFound, reason: "fez barrel is not available")
                        }
                        // ensure we have a capacity value
                        guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                            let maxMonkeys = Int(maxString) else {
                                throw Abort(.internalServerError, reason: "maxCapacity not found")
                        }
                        // return as FezDetailData
                        var fezDetailData = try FezDetailData(
                            fezID: barrel.requireID(),
                            ownerID: barrel.ownerID,
                            fezType: barrel.userInfo["fezType"]?[0] ?? "",
                            title: barrel.name,
                            info: barrel.userInfo["info"]?[0] ?? "",
                            startTime: self.fezTimeString(from: barrel.userInfo["startTime"]?[0] ?? ""),
                            endTime: self.fezTimeString(from: barrel.userInfo["endTime"]?[0] ?? ""),
                            location: barrel.userInfo["location"]?[0] ?? "",
                            seamonkeys: [],
                            waitingList: [],
                            posts: []
                        )
                        // convert UUIDs to users
                        var futureSeamonkeys = [Future<User?>]()
                        for uuid in barrel.modelUUIDs {
                            futureSeamonkeys.append(User.find(uuid, on: req))
                        }
                        // resolve futures
                        return futureSeamonkeys.flatten(on: req).flatMap {
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
                                    fezDetailData.seamonkeys.remove(at: index)
                                    fezDetailData.seamonkeys.insert(blockedMonkey, at: index)
                                }
                            }
                            // populate fezDetailData
                            switch (valids.count, maxMonkeys)  {
                                // unlimited slots
                                case (_, let max) where max == 0:
                                    fezDetailData.seamonkeys = valids
                                // open slots
                                case (let count, let max) where count < max:
                                    fezDetailData.seamonkeys = valids
                                    // add empty slot fezzes
                                    while fezDetailData.seamonkeys.count < max {
                                        let fezMonkey = SeaMonkey(
                                            userID: Settings.shared.friendlyFezID,
                                            username: "AvailableSlot"
                                        )
                                        fezDetailData.seamonkeys.append(fezMonkey)
                                }
                                // full + waiting list
                                case (let count, let max) where count > max:
                                    fezDetailData.seamonkeys = Array(valids[valids.startIndex..<max])
                                    fezDetailData.waitingList = Array(valids[max..<valids.endIndex])
                                // exactly full
                                default:
                                    fezDetailData.seamonkeys = valids
                            }
                            // get posts
                            return try FezPost.query(on: req)
                                .filter(\.fezID == barrel.requireID())
                                .filter(\.authorID !~ blocked)
                                .filter(\.authorID !~ muted)
                                .sort(\.createdAt, .ascending)
                                .all()
                                .map {
                                    (posts) in
                                    // add as FezPostData
                                    fezDetailData.posts = try posts.map { try $0.convertToData() }
                                    let response = Response(http: HTTPResponse(status: .created), using: req)
                                    try response.content.encode(fezDetailData)
                                    return response
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// `POST /api/v3/fez/post/ID/delete`
    ///
    /// Delete a `FezPost`.
    ///
    /// - Parameters: req: The incoming `Request`, provided automatically
    /// - Throws: 403 error if user is not the post author. 404 error if the fez is not
    ///   available. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezDetailData` containing the updated fez discussion.
    func postDeleteHandler(_ req: Request) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(FezPost.self).flatMap {
            (post) in
            // get barrel
            return Barrel.find(post.fezID, on: req)
                .unwrap(or: Abort(.internalServerError, reason: "fez not found"))
                .flatMap {
                    (barrel) in
                    // delete post
                    guard try post.authorID == user.requireID() else {
                        throw Abort(.forbidden, reason: "user cannot delete post")
                    }
                    return post.delete(on: req).flatMap {
                        (_) in
                        // get blocks
                        return try self.getCachedFilters(for: user, on: req).flatMap {
                            (tuple) in
                            let blocked = tuple.0
                            let muted = tuple.1
                            guard !blocked.contains(barrel.ownerID) else {
                                throw Abort(.notFound, reason: "fez barrel is not available")
                            }
                            // ensure we have a capacity value
                            guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                                let maxMonkeys = Int(maxString) else {
                                    throw Abort(.internalServerError, reason: "maxCapacity not found")
                            }
                            // return as FezDetailData
                            var fezDetailData = try FezDetailData(
                                fezID: barrel.requireID(),
                                ownerID: barrel.ownerID,
                                fezType: barrel.userInfo["fezType"]?[0] ?? "",
                                title: barrel.name,
                                info: barrel.userInfo["info"]?[0] ?? "",
                                startTime: self.fezTimeString(from: barrel.userInfo["startTime"]?[0] ?? ""),
                                endTime: self.fezTimeString(from: barrel.userInfo["endTime"]?[0] ?? ""),
                                location: barrel.userInfo["location"]?[0] ?? "",
                                seamonkeys: [],
                                waitingList: [],
                                posts: []
                            )
                            // convert UUIDs to users
                            var futureSeamonkeys = [Future<User?>]()
                            for uuid in barrel.modelUUIDs {
                                futureSeamonkeys.append(User.find(uuid, on: req))
                            }
                            // resolve futures
                            return futureSeamonkeys.flatten(on: req).flatMap {
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
                                        fezDetailData.seamonkeys.remove(at: index)
                                        fezDetailData.seamonkeys.insert(blockedMonkey, at: index)
                                    }
                                }
                                // populate fezDetailData
                                switch (valids.count, maxMonkeys)  {
                                    // unlimited slots
                                    case (_, let max) where max == 0:
                                        fezDetailData.seamonkeys = valids
                                    // open slots
                                    case (let count, let max) where count < max:
                                        fezDetailData.seamonkeys = valids
                                        // add empty slot fezzes
                                        while fezDetailData.seamonkeys.count < max {
                                            let fezMonkey = SeaMonkey(
                                                userID: Settings.shared.friendlyFezID,
                                                username: "AvailableSlot"
                                            )
                                            fezDetailData.seamonkeys.append(fezMonkey)
                                    }
                                    // full + waiting list
                                    case (let count, let max) where count > max:
                                        fezDetailData.seamonkeys = Array(valids[valids.startIndex..<max])
                                        fezDetailData.waitingList = Array(valids[max..<valids.endIndex])
                                    // exactly full
                                    default:
                                        fezDetailData.seamonkeys = valids
                                }
                                // get posts
                                return try FezPost.query(on: req)
                                    .filter(\.fezID == barrel.requireID())
                                    .filter(\.authorID !~ blocked)
                                    .filter(\.authorID !~ muted)
                                    .sort(\.createdAt, .ascending)
                                    .all()
                                    .map {
                                        (posts) in
                                        // add as FezPostData
                                        fezDetailData.posts = try posts.map { try $0.convertToData() }
                                        let response = Response(http: HTTPResponse(status: .created), using: req)
                                        try response.content.encode(fezDetailData)
                                        return response
                                }
                            }
                        }
                    }
            }
        }
    }

    /// `POST /api/v3/fez/ID/unjoin`
    ///
    /// Remove the current user from the FriendlyFez. If the `.maxCapacity` of the fez had
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
    
    /// `POST /api/v3/fez/ID/update`
    ///
    /// Update the specified FriendlyFez with the supplied data.
    ///
    /// - Note: All fields in the supplied `FezContentData` must be filled, just as if the fez
    ///   were being created from scratch. If there is demand, using a set of more efficient
    ///   endpoints instead of this single monolith can be considered.
    ///
    /// - Requires: `FezContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `FezContentData` containing the new fez parameters.
    /// - Throws: 400 error if the data is not valid. 403 error if user is not fez owner.
    ///   A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez info.
    func updateHandler(_ req: Request, data: FezContentData) throws -> Future<FezData> {
        let user = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            guard try barrel.ownerID == user.requireID() else {
                throw Abort(.forbidden, reason: "user does not own fez")
            }
            // see FezContentData.validations()
            try data.validate()
            // update barrel
            barrel.userInfo["fezType"] = [data.fezType]
            barrel.name = data.title
            barrel.userInfo["info"] = [data.info]
            barrel.userInfo["startTime"] = [data.startTime]
            barrel.userInfo["endTime"] = [data.endTime]
            barrel.userInfo["location"] = [data.location]
            barrel.userInfo["minCapacity"] = [String(data.minCapacity)]
            barrel.userInfo["maxCapacity"] = [String(data.maxCapacity)]
            return barrel.save(on: req).flatMap {
                (savedBarrel) in
                // return as  FezData
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
                // ensure we have a capacity value
                guard let maxString = savedBarrel.userInfo["maxCapacity"]?[0],
                    let maxMonkeys = Int(maxString) else {
                        throw Abort(.internalServerError, reason: "maxCapacity not found")
                }
                // convert UUIDs to users
                var futureSeamonkeys = [Future<User?>]()
                for uuid in savedBarrel.modelUUIDs {
                    futureSeamonkeys.append(User.find(uuid, on: req))
                }
                // resolve futures
                return futureSeamonkeys.flatten(on: req).map {
                    (seamonkeys) in
                    // convert valid users to seamonkeys
                    let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
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
        }
    }
    
    /// `POST /api/v3/fez/ID/user/ID/add`
    ///
    /// Add the specified `User` to the specified FriendlyFez barrel.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if user is already in barrel. 403 error if requester is not fez
    ///   owner. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez info.
    func userAddHandler(_ req: Request) throws -> Future<Response> {
        let requester = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            guard try barrel.ownerID == requester.requireID() else {
                throw Abort(.forbidden, reason: "requester does not own fez")
            }
            // ensure we have a capacity value
            guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                let maxMonkeys = Int(maxString) else {
                    throw Abort(.internalServerError, reason: "maxCapacity not found")
            }
            // get user
            return try req.parameters.next(User.self).flatMap {
                (user) in
                // add user
                guard !barrel.modelUUIDs.contains(try user.requireID()) else {
                    throw Abort(.badRequest, reason: "user is already in fez")
                }
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
    
    /// `POST /api/v3/fez/ID/user/ID/remove`
    ///
    /// Remove the specified `User` from the specified FriendlyFez barrel.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if user is not in the barrel. 403 error if requester is not fez
    ///   owner. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez info.
    func userRemoveHandler(_ req: Request) throws -> Future<Response> {
        let requester = try req.requireAuthenticated(User.self)
        // get barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
            }
            guard try barrel.ownerID == requester.requireID() else {
                throw Abort(.forbidden, reason: "requester does not own fez")
            }
            // ensure we have a capacity value
            guard let maxString = barrel.userInfo["maxCapacity"]?[0],
                let maxMonkeys = Int(maxString) else {
                    throw Abort(.internalServerError, reason: "maxCapacity not found")
            }
            // get user
            return try req.parameters.next(User.self).flatMap {
                (user) in
                // remove user
                guard let index = barrel.modelUUIDs.firstIndex(of: try user.requireID()) else {
                    throw Abort(.badRequest, reason: "user is not in fez")
                }
                barrel.modelUUIDs.remove(at: index)
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

// posts can be filtered by author and content
extension FezController: ContentFilterable {}

// posts can contain images
extension FezController: ImageHandler {
    /// The base directory for storing FezPost images.
    var imageDir: String {
        return "images/fez/"
    }
    
    /// The height of FezPost image thumbnails.
    var thumbnailHeight: Int {
        return 100
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
