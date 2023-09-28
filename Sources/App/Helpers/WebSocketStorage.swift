import Fluent
import Redis
import Vapor

public struct UserSocket {
	let socketID: UUID
	let userID: UUID
	let socket: WebSocket
	let groupID: UUID?
	let htmlOutput: Bool

	init(userID: UUID, socket: WebSocket, groupID: UUID? = nil, htmlOutput: Bool = false) {
		self.userID = userID
		self.socket = socket
		socketID = UUID()
		self.groupID = groupID
		self.htmlOutput = htmlOutput
	}
}

extension Application {
	/// This is where we store active WebSockets.
	var websocketStorage: WebSocketStorage {
		get {
			guard let result = self.storage[WebSocketStorageKey.self] else {
				let newResult = WebSocketStorage()
				self.storage[WebSocketStorageKey.self] = newResult
				return newResult
			}
			return result
		}
		set {
			self.storage[WebSocketStorageKey.self] = newValue
		}
	}

	/// This is the datatype that gets stored in UserCacheStorage. Vapor's Services API uses this.
	/// Making this a class instead of a struct. This prevents internal modifications (e.g. adding/removing a value from the dicts) from causing the entire app.storage
	/// getting copied, in the case where app.storage is a value type composed of other value types. The custom setter for app.storage is not thread-safe. So, this is a
	/// workaround for app.storage having a non-thread-safe setter.
	class WebSocketStorage {
		// Stored by user, so userID : [UserSocket]
		var notificationSockets: [UUID: [UserSocket]] = [:]
		// Stored by groupID, so groupID : [UserSocket]
		var groupSockets: [UUID: [UserSocket]] = [:]
	}

	/// Storage key used by Vapor's Services API. Used by UserCache to access its cache data.
	struct WebSocketStorageKey: StorageKey {
		typealias Value = WebSocketStorage
	}

	/// A simple mutex lock provided by Vapor's Services API.. All code blocks that are protected
	/// with this lock's `withLock()` method are serialized against each other.
	struct WebSocketStorageLockKey: LockKey {}

}

extension Request {
	public var webSocketStore: WebSocketStorage {
		.init(request: self)
	}

	public class WebSocketStorage {
		private var request: Request

		public init(request: Request) {
			self.request = request
		}

		// MARK: Notification Sockets
		func getSockets(_ userID: UUID) -> [UserSocket] {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			let cacheResult = cacheLock.withLock {
				request.application.websocketStorage.notificationSockets[userID]
			}
			return cacheResult ?? []
		}

		func getSockets<T: Sequence>(_ userIDs: T) -> [UserSocket] where T.Element == UUID {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			let cacheResult = cacheLock.withLock { () -> [UserSocket] in
				let dict = request.application.websocketStorage.notificationSockets
				return userIDs.flatMap { dict[$0] ?? [] }
			}
			return cacheResult
		}

		func storeSocket(_ ws: UserSocket) {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.notificationSockets[ws.userID] ?? []
				sockets.append(ws)
				request.application.websocketStorage.notificationSockets[ws.userID] = sockets
			}
		}

		func removeSocket(_ ws: UserSocket) {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.notificationSockets[ws.userID] ?? []
				if let index = sockets.firstIndex(where: { $0.socketID == ws.socketID }) {
					sockets.remove(at: index)
					request.application.websocketStorage.notificationSockets[ws.userID] = sockets
				}
			}
		}

		// MARK: Group Sockets
		func getGroupSockets(_ groupID: UUID) -> [UserSocket] {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			let cacheResult = cacheLock.withLock { () -> [UserSocket] in
				return request.application.websocketStorage.groupSockets[groupID] ?? []
			}
			return cacheResult
		}

		func storeGroupSocket(_ ws: UserSocket) throws {
			guard let groupID = ws.groupID else {
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.groupSockets[groupID] ?? []
				sockets.append(ws)
				request.application.websocketStorage.groupSockets[groupID] = sockets
			}
		}

		func removeGroupSocket(_ ws: UserSocket) throws {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			guard let groupID = ws.groupID else {
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.groupSockets[groupID] ?? []
				if let index = sockets.firstIndex(where: { $0.socketID == ws.socketID }) {
					sockets.remove(at: index)
					request.application.websocketStorage.groupSockets[groupID] = sockets
				}
			}
		}

		// MARK: Logout
		func handleUserLogout(_ userID: UUID) async throws {
			var groupSocketsToClose: [UserSocket] = []
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				groupSocketsToClose.append(
					contentsOf: request.application.websocketStorage.notificationSockets[userID] ?? []
				)
				request.application.websocketStorage.notificationSockets[userID] = nil
				for groupSockets in request.application.websocketStorage.groupSockets.values {
					let userGroupSockets = groupSockets.filter { $0.userID == userID }
					if !userGroupSockets.isEmpty, let groupID = userGroupSockets[0].groupID {
						groupSocketsToClose.append(contentsOf: userGroupSockets)
						let openSockets = groupSockets.filter { $0.userID != userID }
						request.application.websocketStorage.groupSockets[groupID] = openSockets
					}
				}
			}
			for userGroupSocket in groupSocketsToClose {
				try await userGroupSocket.socket.close().get()
			}
		}
	}
}
