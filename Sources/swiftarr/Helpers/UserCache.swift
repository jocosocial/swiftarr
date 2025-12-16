import Fluent
import Foundation
import NIOConcurrencyHelpers
import Vapor

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

public struct UserCacheData: Authenticatable, SessionAuthenticatable, Sendable {
	let userID: UUID
	let username: String
	let displayName: String?
	let profileUpdateTime: Date
	let userImage: String?
	let blocks: Set<UUID>?  // This is the 'computed' blocks; includes blocks initiated by both this user and by others.
	let mutes: Set<UUID>?
	let mutewords: [String]?
	let token: String?
	let accessLevel: UserAccessLevel
	let userRoles: Set<UserRoleType>
	let tempQuarantineUntil: Date?
	let preferredPronoun: String?

	init(userID: UUID, user: User, blocks: [UUID]?, mutewords: [String]?) {
		self.userID = userID
		username = user.username
		displayName = user.displayName
		profileUpdateTime = user.profileUpdatedAt
		userImage = user.userImage
		// I actually hate using map in this way--the maps apply to the optionals, not the underlying arrays.
		self.blocks = blocks.map { Set($0) }
		self.mutes = Set(user.mutedUserIDs)  // mutes.map { Set($0) }
		self.mutewords = mutewords
		self.token = user.$token.value??.token ?? nil
		self.accessLevel = user.accessLevel
		self.tempQuarantineUntil = user.tempQuarantineUntil
		self.userRoles = Set(user.roles.map { $0.role })
		self.preferredPronoun = user.preferredPronoun
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
		return UserHeader(
			userID: userID,
			username: username,
			displayName: displayName,
			userImage: userImage,
			preferredPronoun: preferredPronoun
		)
	}

	func getUser(on db: Database) async throws -> User {
		guard let result = try await User.find(userID, on: db) else {
			throw Abort(.internalServerError, reason: "Could not find User in database, but it was in the cache")
		}
		return result
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
	func guardCanModifyContent<T: Reportable>(
		_ content: T,
		customErrorString: String = "user cannot modify this content"
	) throws {
		if let quarantineEndDate = tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined and cannot modify content.")
			}
		}
		let userIsContentCreator = userID == content.authorUUID
		guard
			accessLevel.canEditOthersContent()
				|| (userIsContentCreator && accessLevel.canCreateContent()
					&& (content.moderationStatus == .normal || content.moderationStatus == .modReviewed))
		else {
			throw Abort(.forbidden, reason: customErrorString)
		}
		// If a mod reviews some content, and then the user edits their own content, it's no longer moderator reviewed.
		// This code assumes the content is going to get saved by caller.
		if userIsContentCreator && content.moderationStatus == .modReviewed {
			content.moderationStatus = .normal
		}
	}
}

// MARK: - UCD Authenticators
extension UserCacheData {
	// UserCacheData.BasicAuth lets the Login route auth a UserCacheData object using a basic Authorization header.
	// This auth code uses the async version of verify. Async verify appears to perform better under Locust;
	// I'm guessing that with sync verify we'd end up with all threads busy running Bcrypt when lots of logins came in
	// at once, leading to incoming requests failing.
	struct BasicAuth: AsyncBasicAuthenticator {
		func authenticate(basic: BasicAuthorization, for request: Request) async throws {
			guard let cacheUser = request.userCache.getUser(username: basic.username), cacheUser.accessLevel != .banned,
				let user = try await User.query(on: request.db).filter(\.$id == cacheUser.userID).first()
			else {
				return
			}
			if try await request.password.async.verify(basic.password, created: user.password) {
				request.auth.login(cacheUser)
			}
		}
	}

	// UserCacheData.ServiceAccountBasicAuth authenticates only builtin service accounts (admin, prometheus, THO)
	// using HTTP Basic Authentication with passwords only. This is intended for routes that should only be
	// accessible to these service accounts, not regular users. Tokens are not accepted.
	struct ServiceAccountBasicAuth: AsyncBasicAuthenticator {
		func authenticate(basic: BasicAuthorization, for request: Request) async throws {
			// Only allow service account usernames (case-insensitive check)
			// Uses PrivilegedUser.serviceAccountsWithPasswords for centralized definition
			guard PrivilegedUser.serviceAccountsWithPasswords.contains(basic.username.lowercased()) else {
				return
			}

			guard let cacheUser = request.userCache.getUser(username: basic.username),
				let user = try await User.query(on: request.db).filter(\.$id == cacheUser.userID).first()
			else {
				return
			}

			if try await request.password.async.verify(basic.password, created: user.password) {
				request.auth.login(cacheUser)
			}
		}
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
	struct TokenAuthenticator: AsyncBearerAuthenticator {
		typealias User = UserCacheData

		func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
			if let foundUser = request.userCache.getUser(token: bearer.token), foundUser.accessLevel != .banned {
				request.auth.login(foundUser)
			}
		}
	}

	// UserCacheData.SessionAuthenticator lets routes auth a UserCacheData object from a session ID.
	// Don't use this in API routes, as API routes should use token based auth (or basic auth for login).
	struct SessionAuth: AsyncSessionAuthenticator {
		typealias User = UserCacheData

		func authenticate(sessionID: String, for request: Request) async throws {
			if let userID = UUID(sessionID), let foundUser = request.userCache.getUser(userID),
				let sessionToken = request.session.data["token"], sessionToken == foundUser.token
			{
				request.auth.login(foundUser)
			}
		}
	}
}

extension Application {
	nonisolated(unsafe) fileprivate static var ucs: UserCacheStorage?
	private static let ucsLock: NIOLock = NIOLock()

	/// This is where UserCache stores its in-memory cache.
	static var userCacheStorage: UserCacheStorage {
		get {
			let result = ucsLock.withLock {
				guard let result = ucs else {
					return UserCacheStorage()
				}
				return result
			}
			return result
		}
		set {
			ucsLock.withLock {
				ucs = newValue
			}
		}
	}

	/// This is the datatype that gets stored in UserCacheStorage. Vapor's Services API uses this.
	struct UserCacheStorage {
		var usersByID: [UUID: UserCacheData] = [:]
		var usersByName: [String: UserCacheData] = [:]
		var usersByToken: [String: UserCacheData] = [:]

		mutating func cacheUser(_ data: UserCacheData) {
			if let existing = usersByID[data.userID] {
				usersByName.removeValue(forKey: existing.username.lowercased())
				if let token = existing.token {
					usersByToken.removeValue(forKey: token)
				}
			}
			self.usersByID[data.userID] = data
			self.usersByName[data.username.lowercased()] = data
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
	func initializeUserCache(_ app: Application) async throws {
		if app.environment.arguments.count > 1,
			app.environment.arguments[1].lowercased().hasSuffix("migrate")
		{
			return
		}

		//		let _ = Task {
		var initialStorage = UserCacheStorage()
		let results = try await User.query(on: app.db).with(\.$token).with(\.$roles).with(\.$muteWords).all().get()
		for user in results {
			let userID = try user.requireID()
			let blocks = try await app.redis.getBlocks(for: userID)
			let mutewords = user.muteWords.map { $0.word }
			let cacheData = UserCacheData(userID: userID, user: user, blocks: blocks, mutewords: mutewords)
			initialStorage.cacheUser(cacheData)
		}
		Application.ucs = initialStorage
		//		}
	}

	func getUserHeader(_ username: String) -> UserHeader? {
		let cacheLock = self.locks.lock(for: Application.UserCacheLockKey.self)
		if let user = cacheLock.withLock({ Application.userCacheStorage.usersByName[username.lowercased()] }) {
			return UserHeader(
				userID: user.userID,
				username: user.username,
				displayName: user.displayName,
				userImage: user.userImage,
				preferredPronoun: user.preferredPronoun
			)
		}
		return nil
	}
}

extension Request {
	var userCache: UserCache {
		.init(request: self)
	}

	// UserCache isn't actually the cache. It's a bunch of cache-access methods that extends a Request.
	struct UserCache {
		let request: Request

		// MARK: UserHeaders
		func getHeader(_ userID: UUID) throws -> UserHeader {
			guard let user = getUser(userID) else {
				throw Abort(.internalServerError, reason: "No user found with userID \(userID).")
			}
			return UserHeader(
				userID: userID,
				username: user.username,
				displayName: user.displayName,
				userImage: user.userImage,
				preferredPronoun: user.preferredPronoun
			)
		}

		func getHeader(_ username: String) -> UserHeader? {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			if let user = cacheLock.withLock({
				Application.userCacheStorage.usersByName[username.lowercased()]
			}) {
				return UserHeader(
					userID: user.userID,
					username: user.username,
					displayName: user.displayName,
					userImage: user.userImage,
					preferredPronoun: user.preferredPronoun
				)
			}
			return nil
		}

		func getHeaders(fromDate: Date, forUser: User) throws -> [UserHeader] {
			let userBlocks = try getBlocks(forUser)
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				Application.userCacheStorage.usersByID.filter { cachedUser in
					cachedUser.value.profileUpdateTime >= fromDate && !userBlocks.contains(cachedUser.key)
				}
			})

			// We could do this step above, by mapping instead of filtering, but this moves some of the work out of the lock.
			return users.values.map {
				UserHeader(
					userID: $0.userID,
					username: $0.username,
					displayName: $0.displayName,
					userImage: $0.userImage,
					preferredPronoun: $0.preferredPronoun
				)
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
				Application.userCacheStorage.usersByID[userUUID]
			}
			return cacheResult
		}

		public func getUser(username: String) -> UserCacheData? {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let cacheResult = cacheLock.withLock {
				Application.userCacheStorage.usersByName[username.lowercased()]
			}
			return cacheResult
		}

		public func getUser(token: String) -> UserCacheData? {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let cacheResult = cacheLock.withLock {
				Application.userCacheStorage.usersByToken[token]
			}
			return cacheResult
		}

		func getUsers<IDs: Collection>(_ userIDs: IDs) -> [UserCacheData] where IDs.Element == UUID {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				userIDs.compactMap { Application.userCacheStorage.usersByID[$0] }
			})
			return users
		}

		func getUsers<Names: Collection>(usernames: Names) -> [UserCacheData] where Names.Element == String {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				usernames.compactMap { Application.userCacheStorage.usersByName[$0.lowercased()] }
			})
			return users
		}

		func allUsersWithAccessLevel(_ level: UserAccessLevel) -> [UserCacheData] {
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			let users = cacheLock.withLock({
				Application.userCacheStorage.usersByID.compactMap { $0.value.accessLevel >= level ? $0.value : nil }
			})
			return users
		}

		// MARK: updating
		@discardableResult
		public func updateUser(_ userUUID: UUID) async throws -> UserCacheData {
			let cacheData = try await getUpdatedUserCacheData(userUUID)
			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			// It's possible another thread could add this cache entry while this thread is
			// building it. That's okay.
			cacheLock.withLock {
				Application.userCacheStorage.cacheUser(cacheData)
			}
			return cacheData
		}

		public func updateUsers(_ uuids: [UUID]) async throws {
			let cacheData = try await withThrowingTaskGroup(of: UserCacheData.self, returning: [UserCacheData].self) {
				group in
				for userID in uuids {
					group.addTask { try await getUpdatedUserCacheData(userID) }
				}
				var results = [UserCacheData]()
				for try await ucd in group {
					results.append(ucd)
				}
				return results
			}

			let cacheLock = request.application.locks.lock(for: Application.UserCacheLockKey.self)
			cacheLock.withLock {
				cacheData.forEach { userCacheData in
					Application.userCacheStorage.cacheUser(userCacheData)
				}
			}
		}

		private func getUpdatedUserCacheData(_ userID: UUID) async throws -> UserCacheData {
			async let user = User.query(on: request.db).filter(\.$id == userID)
				.with(\.$token)
				.with(\.$roles)
				.with(\.$muteWords)
				.first()
			async let blocks = try request.redis.getBlocks(for: userID)
			guard let user = try await user else {
				throw Abort(.internalServerError, reason: "user not found")
			}
			let mutewords = user.muteWords.map { $0.word }
			let cacheData = try await UserCacheData(userID: userID, user: user, blocks: blocks, mutewords: mutewords)
			return cacheData
		}
	}
}
