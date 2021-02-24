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

public struct UserCacheData {
	let userID: UUID
	let username: String
	let displayName: String?
	let profileUpdateTime: Date
	let userImage: String?
	let blocks: Set<UUID>?
	let mutes: Set<UUID>?
	let mutewords: [String]?
	let alertwords: [String]?
	
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
		
		mutating func cacheUser(_ data: UserCacheData) {
			self.usersByID[data.userID] = data
			self.usersByName[data.username] = data
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
	struct UserCacheStartup: LifecycleHandler {
		// Load all users into cache at startup.
		func didBoot(_ app: Application) throws {
			if app.environment.arguments.count > 1,
					app.environment.arguments[1].lowercased().hasSuffix("migrate") {
				return
			}
		
			var initialStorage = UserCacheStorage()
			var allUsers: [User]
			// As it happens, we can diagnose several startup-time malfunctions here, as this is usually the first query each launch.
			do {
				allUsers = try User.query(on: app.db).all().wait()
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
				let blockFuture = app.redis.get(redisKey, as: [UUID].self)
			
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
				
					let cacheData = UserCacheData(userID: userID, user: user, blocks: blocks,
							mutes: mutes, mutewords: muteWords, alertwords: alertWords)
					initialStorage.cacheUser(cacheData)
				}
				try futures.wait()
			}
			app.userCacheStorage = initialStorage
		}
	}

}

extension Request {
	public var userCache: UserCache {
		.init(request: self)
	}
	
	public struct UserCache {
		let request: Request
		
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
		
		func getHeaders(_ userIDs: [UUID]) -> [UserHeader] {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				userIDs.compactMap { request.application.userCacheStorage.usersByID[$0] }
			})
			return users.map { $0.makeHeader() }
		}
		
		func getBlocks(_ user: User) throws -> Set<UUID> {
			return try getUser(user).blocks ?? []
		}
		
		func getBlocks(_ userUUID: UUID) -> Set<UUID> {
			return getUser(userUUID)?.blocks ?? []
		}
		
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
					var storage = request.application.userCacheStorage
					cacheData.forEach { userCacheData in
						storage.cacheUser(userCacheData)
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
			let blockFuture = request.redis.get(redisKey, as: [UUID].self)
			
			// Build an entry for this user
			return User.find(userUUID, on: request.db)
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
				
					let cacheData = UserCacheData(userID: userUUID, user: user, blocks: blocks,
							mutes: mutes, mutewords: muteWords, alertwords: alertWords)
					return cacheData
				}
		}

	}
}

