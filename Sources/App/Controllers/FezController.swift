import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of /api/v3/fez/* route endpoints and handler functions related
/// to FriendlyFez/LFG barrels.

struct FezController: RouteCollection {
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
        // convenience route group for all /api/v3/fez endpoints
        let fezRoutes = routes.grouped("api", "v3", "fez")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthMiddleware = Token.authenticator()
        
        // set protected route groups
        let sharedAuthGroup = fezRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = fezRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        sharedAuthGroup.get("joined", use: joinedHandler)
        sharedAuthGroup.get("open", use: openHandler)
        sharedAuthGroup.get("types", use: typesHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.get(":barrel_id", use: fezHandler)
        tokenAuthGroup.post(":barrel_id", "cancel", use: cancelHandler)
        tokenAuthGroup.post("create", use: createHandler)
        tokenAuthGroup.post(":barrel_id", "join", use: joinHandler)
        tokenAuthGroup.get("owner", use: ownerHandler)
        tokenAuthGroup.post(":barrel_id", "post", use: postAddHandler)
        tokenAuthGroup.post("post", ":post_id", "delete", use: postDeleteHandler)
        tokenAuthGroup.post(":barrel_id", "unjoin", use: unjoinHandler)
        tokenAuthGroup.post(":barrel_id", "update", use: updateHandler)
        tokenAuthGroup.post("user", ":user_id", "add", use: userAddHandler)
        tokenAuthGroup.post(":barrel_id", "user", ":user_id", "remove", use: userRemoveHandler)
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
    func joinedHandler(_ req: Request) throws -> EventLoopFuture<[FezData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get fez barrels
        return Barrel.query(on: req.db)
            .filter(\.$barrelType == .friendlyFez)
            .all()
            .throwingFlatMap { (barrels) in
				let blocked = req.userCache.getBlocks(userID)
				// get user's barrels
				var userBarrels = [Barrel]()
				for barrel in barrels {
					if barrel.modelUUIDs.contains(userID) {
						userBarrels.append(barrel)
					}
				}
				// convert to FezData
				let fezzesData = try userBarrels.map {
					(barrel) -> EventLoopFuture<FezData> in
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
					var futureSeamonkeys = [EventLoopFuture<User?>]()
					for uuid in barrel.modelUUIDs {
						futureSeamonkeys.append(User.find(uuid, on: req.db))
					}
					// resolve futures
					return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing {
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
				return fezzesData.flatten(on: req.eventLoop)
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
    func openHandler(_ req: Request) throws -> EventLoopFuture<[FezData]> {
        let user = try req.auth.require(User.self)
		// respect blocks
		let blocked = try req.userCache.getBlocks(user)
		// get fez barrels
		return Barrel.query(on: req.db)
			.filter(\.$barrelType == .friendlyFez)
			.filter(\.$ownerID !~ blocked)
			.all()
			.throwingFlatMap { (barrels) in
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
					(barrel) -> EventLoopFuture<FezData> in
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
					var futureSeamonkeys = [EventLoopFuture<User?>]()
					for uuid in barrel.modelUUIDs {
						futureSeamonkeys.append(User.find(uuid, on: req.db))
					}
					// resolve futures
					return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing() {
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
				return fezzesData.flatten(on: req.eventLoop)
		}
    }
    
    /// `/GET /api/v3/fez/types`
    ///
    /// Retrieve a list of all values for `FezType` as strings.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[String]` containing the `.label` value for each type.
    func typesHandler(_ req: Request) throws -> EventLoopFuture<[String]> {
        return req.eventLoop.future(FezType.allCases.map { $0.label })
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
    func cancelHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        // get barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
			do {
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
				var futureSeamonkeys = [EventLoopFuture<User?>]()
				for uuid in barrel.modelUUIDs {
					futureSeamonkeys.append(User.find(uuid, on: req.db))
				}
				// resolve futures
				return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing {
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
			catch {
				return req.eventLoop.makeFailedFuture(error)
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
    func createHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        // see `FezCreateData.validations()`
        try FezContentData.validate(content: req)
        let data = try req.content.decode(FezContentData.self)
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
        return barrel.save(on: req.db).flatMapThrowing {
            // return as FezData
            var fezData = try FezData(
                fezID: barrel.requireID(),
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
            let response = Response(status: .created)
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
    func fezHandler(_ req: Request) throws -> EventLoopFuture<FezDetailData> {
        let user = try req.auth.require(User.self)
        // get barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                return req.eventLoop.makeFailedFuture(
                		Abort(.badRequest, reason: "barrel is not type .friendlyFez"))
            }
            // get blocks
            return Event.getCachedFilters(for: user, on: req).flatMap { (filters) in
				do {
					guard !filters.blocked.contains(barrel.ownerID) else {
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
					var futureSeamonkeys = [EventLoopFuture<User?>]()
					for uuid in barrel.modelUUIDs {
						futureSeamonkeys.append(User.find(uuid, on: req.db))
					}
					// resolve futures
					return futureSeamonkeys.flatten(on: req.eventLoop).flatMap { (seamonkeys) in
						do {
							// convert valid users to seamonkeys
							let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
							// masquerade blocked users
							for (index, seamonkey) in valids.enumerated() {
								if filters.blocked.contains(seamonkey.userID) {
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
							return try FezPost.query(on: req.db)
								.filter(\.$fez.$id == barrel.requireID())
								.filter(\.$author.$id !~ filters.blocked)
								.filter(\.$author.$id !~ filters.muted)
								.sort(\.$createdAt, .ascending)
								.all()
								.flatMapThrowing {
									(posts) in
									// add as FezPostData
									fezDetailData.posts = try posts.map { try $0.convertToData() }
									return fezDetailData
								}
						}
						catch {
							return req.eventLoop.makeFailedFuture(error)
						}
					}
				}
				catch {
					return req.eventLoop.makeFailedFuture(error)
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
    func joinHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        // get barrel
        guard let str = req.parameters.get("barrel_id"), let barrelID = UUID(str) else {
            throw Abort(.badRequest, reason: "FriendlyFez ID is not a UUID.")
        }
        return Barrel.find(barrelID, on: req.db)
			.unwrap(or: Abort(.badRequest, reason: "FriendlyFez does not exist."))
			.throwingFlatMap { (barrel) in
				// respect blocks
				let blocked = try req.userCache.getBlocks(user)
				guard barrel.barrelType == .friendlyFez else {
					throw Abort(.badRequest, reason: "barrel is not type .friendlyFez")
				}
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
				return barrel.save(on: req.db).map { barrel }.throwingFlatMap { (savedBarrel) in
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
					var futureSeamonkeys = [EventLoopFuture<User?>]()
					for uuid in barrel.modelUUIDs {
						futureSeamonkeys.append(User.find(uuid, on: req.db))
					}
					// resolve futures
					return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing { (seamonkeys) in
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
						let response = Response(status: .created)
						try response.content.encode(fezData)
						return response
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
    func ownerHandler(_ req: Request) throws -> EventLoopFuture<[FezData]> {
        let user = try req.auth.require(User.self)
        // get owned fez barrels
        return try Barrel.query(on: req.db)
            .filter(\.$ownerID == user.requireID())
            .filter(\.$barrelType == .friendlyFez)
            .all()
            .flatMap { (barrels) in
				do {
					// convert to FezData
					let fezzesData = try barrels.map { (barrel) -> EventLoopFuture<FezData> in
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
						var futureSeamonkeys = [EventLoopFuture<User?>]()
						for uuid in barrel.modelUUIDs {
							futureSeamonkeys.append(User.find(uuid, on: req.db))
						}
						// resolve futures
						return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing { (seamonkeys) in
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
					return fezzesData.flatten(on: req.eventLoop)
				}
				catch {
					return req.eventLoop.makeFailedFuture(error)
				}
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
    func postAddHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        // see PostContentData.validations()
        try PostCreateData.validate(content: req)
        let data = try req.content.decode(PostCreateData.self)
        // get fez
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                return req.eventLoop.makeFailedFuture(
                		Abort(.badRequest, reason: "barrel is not type .friendlyFez"))
            }
            // process image
            return self.processImage(data: data.imageData, forType: .forumPost, on: req).throwingFlatMap { (filename) in
                // create post
                let post = try FezPost(fez: barrel, author: user, text: data.text, image: filename)
                return post.save(on: req.db)
                	.and(FezPost.getCachedFilters(for: user, on: req)).flatMap { (_, filters) in
						do {
							guard !filters.blocked.contains(barrel.ownerID) else {
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
							var futureSeamonkeys = [EventLoopFuture<User?>]()
							for uuid in barrel.modelUUIDs {
								futureSeamonkeys.append(User.find(uuid, on: req.db))
							}
							// resolve futures
							return futureSeamonkeys.flatten(on: req.eventLoop).flatMap { (seamonkeys) in
								do {
									// convert valid users to seamonkeys
									let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
									// masquerade blocked users
									for (index, seamonkey) in valids.enumerated() {
										if filters.blocked.contains(seamonkey.userID) {
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
									return try FezPost.query(on: req.db)
										.filter(\.$fez.$id == barrel.requireID())
										.filter(\.$author.$id !~ filters.blocked)
										.filter(\.$author.$id !~ filters.muted)
										.sort(\.$createdAt, .ascending)
										.all()
										.flatMapThrowing { (posts) in
											// add as FezPostData
											fezDetailData.posts = try posts.map { try $0.convertToData() }
											let response = Response(status: .created)
											try response.content.encode(fezDetailData)
											return response
									}
								}
								catch {
									return req.eventLoop.makeFailedFuture(error)
								}
							}
						}
						catch {
							return req.eventLoop.makeFailedFuture(error)
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
    func postDeleteHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post
        return FezPost.findFromParameter("post_id", on: req).flatMap { (post) in
            // get barrel
            return Barrel.find(post.fez.id, on: req.db)
                .unwrap(or: Abort(.internalServerError, reason: "fez not found"))
                .flatMap { (barrel) in
                    // delete post
                    guard post.author.id == userID else {
                        return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot delete post"))
                    }
                    return post.delete(on: req.db).flatMap { (_) in
                        // get blocks
                        return FezPost.getCachedFilters(for: user, on: req).flatMap { (filters) in
							do {
								guard !filters.blocked.contains(barrel.ownerID) else {
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
								var futureSeamonkeys = [EventLoopFuture<User?>]()
								for uuid in barrel.modelUUIDs {
									futureSeamonkeys.append(User.find(uuid, on: req.db))
								}
								// resolve futures
								return futureSeamonkeys.flatten(on: req.eventLoop).flatMap { (seamonkeys) in
									do {
										// convert valid users to seamonkeys
										let valids = try seamonkeys.compactMap { try $0?.convertToSeaMonkey() }
										// masquerade blocked users
										for (index, seamonkey) in valids.enumerated() {
											if filters.blocked.contains(seamonkey.userID) {
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
										return try FezPost.query(on: req.db)
											.filter(\.$fez.$id == barrel.requireID())
											.filter(\.$author.$id !~ filters.blocked)
											.filter(\.$author.$id !~ filters.muted)
											.sort(\.$createdAt, .ascending)
											.all()
											.flatMapThrowing { (posts) in
												// add as FezPostData
												fezDetailData.posts = try posts.map { try $0.convertToData() }
												let response = Response(status: .created)
												try response.content.encode(fezDetailData)
												return response
										}
									}
									catch {
										return req.eventLoop.makeFailedFuture(error)
									}
								}
                            }
                            catch {
                            	return req.eventLoop.makeFailedFuture(error)
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
    func unjoinHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "barrel is not type .friendlyFez"))
            }
			// ensure we have a capacity value
			guard let maxString = barrel.userInfo["maxCapacity"]?[0], let maxMonkeys = Int(maxString) else {
					return req.eventLoop.makeFailedFuture(
							Abort(.internalServerError, reason: "maxCapacity not found"))
			}
			// remove user
			if let index = barrel.modelUUIDs.firstIndex(of: userID) {
				barrel.modelUUIDs.remove(at: index)
			}
			return barrel.save(on: req.db).throwingFlatMap { (_) in
					// return as FezData
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
					var futureSeamonkeys = [EventLoopFuture<User?>]()
					for uuid in barrel.modelUUIDs {
						futureSeamonkeys.append(User.find(uuid, on: req.db))
					}
					// resolve futures
					return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing { (seamonkeys) in
						// get blocks to respect later
						let blocked = req.userCache.getBlocks(userID)
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
						let response = Response(status: .noContent)
						try response.content.encode(fezData)
						return response
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
    func updateHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		// see FezContentData.validations()
        try FezContentData.validate(content: req)
        let data = try req.content.decode(FezContentData.self)        
        // get barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                return req.eventLoop.makeFailedFuture(
						Abort(.badRequest, reason: "barrel is not type .friendlyFez"))
            }
            guard barrel.ownerID == userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user does not own fez"))
            }
            // update barrel
            barrel.userInfo["fezType"] = [data.fezType]
            barrel.name = data.title
            barrel.userInfo["info"] = [data.info]
            barrel.userInfo["startTime"] = [data.startTime]
            barrel.userInfo["endTime"] = [data.endTime]
            barrel.userInfo["location"] = [data.location]
            barrel.userInfo["minCapacity"] = [String(data.minCapacity)]
            barrel.userInfo["maxCapacity"] = [String(data.maxCapacity)]
            return barrel.save(on: req.db).flatMap { (_) in
				do {
					// return as  FezData
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
					// ensure we have a capacity value
					guard let maxString = barrel.userInfo["maxCapacity"]?[0],
						let maxMonkeys = Int(maxString) else {
							throw Abort(.internalServerError, reason: "maxCapacity not found")
					}
					// convert UUIDs to users
					var futureSeamonkeys = [EventLoopFuture<User?>]()
					for uuid in barrel.modelUUIDs {
						futureSeamonkeys.append(User.find(uuid, on: req.db))
					}
					// resolve futures
					return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing {
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
				catch {
					return req.eventLoop.makeFailedFuture(error)
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
    func userAddHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
        // get barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                return req.eventLoop.makeFailedFuture(
                		Abort(.badRequest, reason: "barrel is not type .friendlyFez"))
            }
            guard barrel.ownerID == requesterID else {
				return req.eventLoop.makeFailedFuture(
               			Abort(.forbidden, reason: "requester does not own fez"))
            }
            // ensure we have a capacity value
            guard let maxString = barrel.userInfo["maxCapacity"]?[0], let maxMonkeys = Int(maxString) else {
				return req.eventLoop.makeFailedFuture(
 						Abort(.internalServerError, reason: "maxCapacity not found"))
            }
            // get user
            return User.findFromParameter("user_id", on: req).addModelID().flatMap { (user, userID) in
                // add user
                guard !barrel.modelUUIDs.contains(userID) else {
					return req.eventLoop.makeFailedFuture(
                    		Abort(.badRequest, reason: "user is already in fez"))
                }
                barrel.modelUUIDs.append(userID)
                return barrel.save(on: req.db).flatMap { (_) in
					do {
						// return as FezData
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
						var futureSeamonkeys = [EventLoopFuture<User?>]()
						for uuid in barrel.modelUUIDs {
							futureSeamonkeys.append(User.find(uuid, on: req.db))
						}
						// resolve futures
						return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing {
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
							let response = Response(status: .created)
							try response.content.encode(fezData)
							return response
						}
					}
					catch {
						return req.eventLoop.makeFailedFuture(error)
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
    func userRemoveHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
        // get barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            guard barrel.barrelType == .friendlyFez else {
                return req.eventLoop.makeFailedFuture(
                		Abort(.badRequest, reason: "barrel is not type .friendlyFez"))
            }
            guard barrel.ownerID == requesterID else {
                return req.eventLoop.makeFailedFuture(
						Abort(.forbidden, reason: "requester does not own fez"))
            }
            // ensure we have a capacity value
            guard let maxString = barrel.userInfo["maxCapacity"]?[0], let maxMonkeys = Int(maxString) else {
                return req.eventLoop.makeFailedFuture(
						Abort(.internalServerError, reason: "maxCapacity not found"))
            }
            // get user
            return User.findFromParameter("user_id", on: req).addModelID().flatMap { (user, userID) in
                // remove user
                guard let index = barrel.modelUUIDs.firstIndex(of: userID) else {
                     return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user is not in fez"))
                }
                barrel.modelUUIDs.remove(at: index)
                return barrel.save(on: req.db).flatMap { (_) in
					do {
						// return as FezData
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
						var futureSeamonkeys = [EventLoopFuture<User?>]()
						for uuid in barrel.modelUUIDs {
							futureSeamonkeys.append(User.find(uuid, on: req.db))
						}
						// resolve futures
						return futureSeamonkeys.flatten(on: req.eventLoop).flatMapThrowing {
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
							let response = Response(status: .noContent)
							try response.content.encode(fezData)
							return response
						}
					}
					catch {
						return req.eventLoop.makeFailedFuture(error)
					}
                }
            }
        }
    }

}

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
