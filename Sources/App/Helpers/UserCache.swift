import Foundation
import Vapor
import Fluent
import Redis
import NIO
import PostgresNIO

// With ~2000 users at an average of ~1K per UserCacheData, an in-memory cache of all users would take
// up about 2 Megs of space. We should easily be able to handle this size cache. 
// 
// So, UserCache is designed without a cache eviction mechanism, and it's designed for synchronous
// access when getting cache entries. This means that it must always have info on every user in the db.
// This means that when any of a user's attributes that appear in UserCacheData are changed you'll need
// to call updateUser() on that user.
//
// Because UserCache is shared app-wide, concurrency is a concern. Access to the dictionary that stores
// all the UserCacheData entries is protected by a mutex lock. UserCacheData structs are immutable, their
// properties and sub-structs are immutable, and UserCacheDatas can only be wholly replaced in the cache--
// you cannot update by mutating an existing UCD in the dict. 
//
// Code that creates a new User must defer returning results to the client until the Update future completes,
// to prevent a race where a new user immediately makes a call which processes before the cache is updated.
// For all other updates, it's okay if eventual consistency is okay.

public struct UserCacheData: Authenticatable, SessionAuthenticatable {
	let userID: UUID
	let username: String
	let displayName: String?
	let profileUpdateTime: Date
	let userImage: String?
	let blocks: Set<UUID>?
	let mutes: Set<UUID>?
	let mutewords: [String]?
	let alertwords: [String]?
	let token: String?
	let accessLevel: UserAccessLevel
	let tempQuarantineUntil: Date?
	
	init(userID: UUID, user: User, blocks: [UUID]?, mutes: [UUID]?, mutewords: [String]?, alertwords: [String]?) {
		self.userID = userID
		username = user.username
		displayName = user.displayName
		profileUpdateTime = user.profileUpdatedAt
		userImage = user.userImage
		// I actually hate using map in this way--the maps apply to the optionals, not the underlying arrays.
		self.blocks = blocks.map { Set($0) }
		self.mutes = mutes.map { Set($0) }
		self.mutewords = mutewords
		self.alertwords = alertwords
		self.token = user.$token.value??.token ?? nil
		self.accessLevel = user.accessLevel
		self.tempQuarantineUntil = user.tempQuarantineUntil
	}
	
	// Used by sessionAuthenticatable, but this doesn't go into the cookie.
	public var sessionID: String {
		self.userID.uuidString
	}

	func getBlocks() -> Set<UUID> {
		return blocks ?? []
	}
		
	func getMutes() -> Set<UUID> {
		return mutes ?? []
	}
	
	func makeHeader() -> UserHeader {
		return UserHeader(userID: userID, username: username, displayName: displayName, userImage: userImage)
	}

	// UserCacheData.TokeAuthenticator lets routes auth a UserCacheData object from a token instead of 
	// using Token.authenticator to auth a User object.
	// That is, a request comes in with a Token in the bearer authentication header, this Auth middleware 
	// uses the token to authenticate a UserCacheData for the caller and adds the UCD to req.auth. The route
	// can then get the UserCacheData from req.auth and use it to do stuff. Fetching a UCD is much faster than a
	// User database query. 
	//
	// However, route handlers that need the User object to do their job might as well auth with Token.authenticator,
	// since the database query is 'free'.
	struct TokenAuthenticator: BearerAuthenticator {
		typealias User = App.UserCacheData

		func authenticate(bearer: BearerAuthorization, for request: Request) -> EventLoopFuture<Void> {
			if let foundUser = request.userCache.getUser(token: bearer.token) {
				request.auth.login(foundUser)
			}
			return request.eventLoop.makeSucceededFuture(())
		}
	}

	// UserCacheData.SessionAuthenticator lets routes auth a UserCacheData object from a session ID. 
	// Don't use this in API routes, as API routes should use token based auth (or basic auth for login).
	struct SessionAuth: SessionAuthenticator {
		typealias User = App.UserCacheData
		
		func authenticate(sessionID: String, for request: Request) -> EventLoopFuture<Void> {
			if let userID = UUID(sessionID), let foundUser = request.userCache.getUser(userID) {
				request.auth.login(foundUser)
			}
			return request.eventLoop.makeSucceededFuture(())
		}
	}
	
	/// Ensures that either the receiver can edit/delete other users' content (that is, they're a moderator), or that 
    /// they authored the content they're trying to modify/delete themselves, and still have rights to edit
	/// their own content (that is, they aren't banned/quarantined).
	func guardCanCreateContent(customErrorString: String = "user cannot modify this content") throws {
		if let quarantineEndDate = tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined; \(customErrorString)")
			}
		}
		guard accessLevel.canCreateContent() else {
			throw Abort(.forbidden, reason: customErrorString)
		}
	}
    
    /// Ensures that either the receiver can edit/delete other users' content (that is, they're a moderator), or that 
    /// they authored the content they're trying to modify/delete themselves, and still have rights to edit
	/// their own content (that is, they aren't banned/quarantined).
	func guardCanModifyContent<T: Reportable>(_ content: T, customErrorString: String = "user cannot modify this content") throws {
		if let quarantineEndDate = tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined and cannot modify content.")
			}
		}
		let userIsContentCreator = userID == content.authorUUID
		guard accessLevel.canEditOthersContent() || (userIsContentCreator && accessLevel.canCreateContent() &&
				(content.moderationStatus == .normal || content.moderationStatus == .modReviewed)) else {
			throw Abort(.forbidden, reason: customErrorString)
		}
		// If a mod reviews some content, and then the user edits their own content, it's no longer moderator reviewed.
		// This code assumes the content is going to get saved by caller.
		if userIsContentCreator && content.moderationStatus == .modReviewed {
			content.moderationStatus = .normal
		}
	}
}


extension Application {
 	/// This is where UserCache stores its in-memory cache.
    var userCacheStorage: UserCacheStorage {
        get {
            guard let result = self.storage[UserCacheStorageKey.self] else {
				return UserCacheStorage()
            }
            return result
        }
 		set {
            self.storage[UserCacheStorageKey.self] = newValue
        }   
	}

	/// This is the datatype that gets stored in UserCacheStorage. Vapor's Services API uses this.
	struct UserCacheStorage {
		var usersByID: [UUID : UserCacheData] = [:]
		var usersByName: [String : UserCacheData] = [:]
		var usersByToken: [String : UserCacheData] = [:]
		
		mutating func cacheUser(_ data: UserCacheData) {
			if let existing = usersByID[data.userID] {
				usersByName.removeValue(forKey: existing.username)
				if let token = existing.token {
					usersByToken.removeValue(forKey: token)
				}
			}
			self.usersByID[data.userID] = data
			self.usersByName[data.username] = data
			if let token = data.token {
				self.usersByToken[token] = data
			}
		}
	}
	
	/// Storage key used by Vapor's Services API. Used by UserCache to access its cache data.
	struct UserCacheStorageKey: StorageKey {
		typealias Value = UserCacheStorage
	}
	
	/// A simple mutex lock provided by Vapor's Services API.. All code blocks that are protected 
	/// with this lock's `withLock()` method are serialized against each other. 
	struct UserCacheLockKey: LockKey {}

	/// After boot but before handling requests, this code runs to fill the cache with data on all known
	/// `User`s. LifecycleHandler is another part of Vapor's Services API.
	/// Load all users into cache at startup.
	func initializeUserCache(_ app: Application) throws {
		if app.environment.arguments.count > 1,
				app.environment.arguments[1].lowercased().hasSuffix("migrate") {
			return
		}
	
		var initialStorage = UserCacheStorage()
		var allUsers: [User]
		// As it happens, we can diagnose several startup-time malfunctions here, as this is usually the first query each launch.
		do {
			allUsers = try User.query(on: app.db).with(\.$token).all().wait()
		}
		catch let error as NIO.IOError where error.errnoCode == 61 {
			app.logger.critical("Initial connection to Postgres failed. Is the db up and running?")
			throw error
		}
		catch let error as PostgresNIO.PostgresError {
			app.logger.critical("Initial attempt to access Swiftarr DB tables failed. Is the DB set up (all migrations run)?")
			throw error
		}
		try allUsers.forEach { user in
			let userID = try user.requireID()
			let barrelFuture = Barrel.query(on: app.db)
				.filter(\.$ownerID == userID)
				.filter(\.$barrelType ~~ [.userMute, .keywordMute, .keywordAlert])
				.all()
				
			// Redis stores blocks as users you've blocked AND users who have blocked you,
			// for all subaccounts of both you and the other user.
			let redisKey: RedisKey = "rblocks:\(userID.uuidString)"
			let blockFuture = app.redis.smembers(of: redisKey, as: UUID.self)
		
			let futures = barrelFuture.and(blockFuture).map { (barrels, blocks) in 
				var mutes: [UUID]?
				var muteWords: [String]?
				var alertWords: [String]?
				for barrel in barrels {
					switch barrel.barrelType {
						case .userMute: mutes = barrel.modelUUIDs
						case .keywordMute: muteWords = barrel.userInfo["muteWords"]
						case .keywordAlert: alertWords = barrel.userInfo["alertWords"]
						default: continue
					}
				}
				let compactBlocks = blocks.compactMap { $0 }
				let cacheData = UserCacheData(userID: userID, user: user, blocks: compactBlocks,
						mutes: mutes, mutewords: muteWords, alertwords: alertWords)
				initialStorage.cacheUser(cacheData)
			}
			try futures.wait()
		}
		app.userCacheStorage = initialStorage
	}

}

extension Request {
	public var userCache: UserCache {
		.init(request: self)
	}
	
	public struct UserCache {
		let request: Request
		
// MARK: UserHeaders
		func getHeader(_ userID: UUID) throws -> UserHeader {
			guard let user = getUser(userID) else {
				throw Abort(.internalServerError, reason: "getUser should always return a cached value.")
			}
			return UserHeader(userID: userID, username: user.username, 
					displayName: user.displayName, userImage: user.userImage)
		}
		
		func getHeader(_ username: String) -> UserHeader? {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			if let user = cacheLock.withLock({
				request.application.userCacheStorage.usersByName[username]
			}) {
				return UserHeader(userID: user.userID, username: user.username, 
						displayName: user.displayName, userImage: user.userImage)
			}
			return nil
		}
		
		func getHeaders(fromDate: Date, forUser: User) throws -> [UserHeader] {
			let userBlocks = try getBlocks(forUser)
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				request.application.userCacheStorage.usersByID.filter { cachedUser in
					cachedUser.value.profileUpdateTime >= fromDate && !userBlocks.contains(cachedUser.key)
				}
			})
			
			// We could do this step above, by mapping instead of filtering, but this moves some of the work out of the lock.
			return  users.values.map {
				UserHeader(userID: $0.userID, username: $0.username, displayName: $0.displayName, userImage: $0.userImage)
			}
		}
		
		func getHeaders<IDs: Collection>(_ userIDs: IDs) -> [UserHeader] where IDs.Element == UUID {
			return getUsers(userIDs).map { $0.makeHeader() }
		}
		
		func getHeaders<Names: Collection>(usernames: Names) -> [UserHeader] where Names.Element == String {
			return getUsers(usernames: usernames).map { $0.makeHeader() }
		}
		
// MARK: Blocks
		func getBlocks(_ user: User) throws -> Set<UUID> {
			return try getUser(user).blocks ?? []
		}
		
		func getBlocks(_ userUUID: UUID) -> Set<UUID> {
			return getUser(userUUID)?.blocks ?? []
		}
		
// MARK: UserCacheData
		func getUser(_ user: User) throws -> UserCacheData {
			guard let result = try getUser(user.requireID()) else {
				throw Abort(.internalServerError, reason: "getUser should always return a cached value.")
			}
			return result
		}
		
		public func getUser(_ userUUID: UUID) -> UserCacheData? {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let cacheResult = cacheLock.withLock {
				request.application.userCacheStorage.usersByID[userUUID]
			}
			return cacheResult
		}
		
		public func getUser(token: String) -> UserCacheData? {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let cacheResult = cacheLock.withLock {
				request.application.userCacheStorage.usersByToken[token]
			}
			return cacheResult
		}
		
		func getUsers<IDs: Collection>(_ userIDs: IDs) -> [UserCacheData] where IDs.Element == UUID {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				userIDs.compactMap { request.application.userCacheStorage.usersByID[$0] }
			})
			return users
		}
		
		func getUsers<Names: Collection>(usernames: Names) -> [UserCacheData] where Names.Element == String {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				usernames.compactMap { request.application.userCacheStorage.usersByName[$0] }
			})
			return users
		}
		
// MARK: updating		
		@discardableResult
		public func updateUser(_ userUUID: UUID) -> EventLoopFuture<UserCacheData> {
			return getUpdatedUserCacheData(userUUID).map { cacheData in	
				let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
				// It's possible another thread could add this cache entry while this thread is
				// building it. That's okay.
				cacheLock.withLock {
					request.application.userCacheStorage.cacheUser(cacheData)
				}
				return cacheData
			}
		}
		
		public func updateUsers(_ uuids: [UUID]) -> EventLoopFuture<Void> {
			let futures: [EventLoopFuture<UserCacheData>] = uuids.map { userUUID in
				return getUpdatedUserCacheData(userUUID)
			}
			return futures.flatten(on: request.eventLoop).map { cacheData in
				let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
				cacheLock.withLock {
					cacheData.forEach { userCacheData in
						request.application.userCacheStorage.cacheUser(userCacheData)
					}
				}
			}
		}
		
		private func getUpdatedUserCacheData(_ userUUID: UUID) -> EventLoopFuture<UserCacheData> {
			let barrelFuture = Barrel.query(on: request.db)
					.filter(\.$ownerID == userUUID)
					.filter(\.$barrelType ~~ [.userMute, .keywordMute, .keywordAlert])
					.all()
           		
			// Redis stores blocks as users you've blocked AND users who have blocked you,
			// for all subaccounts of both you and the other user.
			let redisKey: RedisKey = "rblocks:\(userUUID.uuidString)"
			let blockFuture = request.redis.smembers(of: redisKey, as: UUID.self)
			
			// Build an entry for this user
			return User.query(on: request.db).filter(\.$id == userUUID).with(\.$token).first()
					.unwrap(or: Abort(.internalServerError, reason: "user not found"))
					.and(barrelFuture)
					.and(blockFuture)
					.map { (arg0, blocks) in 
				let (user, barrels) = arg0
				var mutes: [UUID]?
				var muteWords: [String]?
				var alertWords: [String]?
				for barrel in barrels {
					switch barrel.barrelType {
						case .userMute: mutes = barrel.modelUUIDs
						case .keywordMute: muteWords = barrel.userInfo["muteWords"]
						case .keywordAlert: alertWords = barrel.userInfo["alertWords"]
						default: continue
					}
				}
			
				let compactBlocks = blocks.compactMap { $0 }
				let cacheData = UserCacheData(userID: userUUID, user: user, blocks: compactBlocks,
						mutes: mutes, mutewords: muteWords, alertwords: alertWords)
				return cacheData
			}
		}
	}
}

