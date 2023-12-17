import Fluent
import Redis
import Vapor

public struct UserSocket {
	let socketID: UUID
	let userID: UUID
	let socket: WebSocket
	let chatGroupID: UUID?
	let htmlOutput: Bool

	init(userID: UUID, socket: WebSocket, chatGroupID: UUID? = nil, htmlOutput: Bool = false) {
		self.userID = userID
		self.socket = socket
		socketID = UUID()
		self.chatGroupID = chatGroupID
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
		// Stored by chatGroupID, so chatGroupID : [UserSocket]
		var chatGroupSockets: [UUID: [UserSocket]] = [:]
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

		// MARK: ChatGroup Sockets
		func getChatGroupSockets(_ chatGroupID: UUID) -> [UserSocket] {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			let cacheResult = cacheLock.withLock { () -> [UserSocket] in
				return request.application.websocketStorage.chatGroupSockets[chatGroupID] ?? []
			}
			return cacheResult
		}

		func storeChatGroupSocket(_ ws: UserSocket) throws {
			guard let chatGroupID = ws.chatGroupID else {
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.chatGroupSockets[chatGroupID] ?? []
				sockets.append(ws)
				request.application.websocketStorage.chatGroupSockets[chatGroupID] = sockets
			}
		}

		func removeChatGroupSocket(_ ws: UserSocket) throws {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			guard let chatGroupID = ws.chatGroupID else {
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.chatGroupSockets[chatGroupID] ?? []
				if let index = sockets.firstIndex(where: { $0.socketID == ws.socketID }) {
					sockets.remove(at: index)
					request.application.websocketStorage.chatGroupSockets[chatGroupID] = sockets
				}
			}
		}

		// MARK: Logout
		func handleUserLogout(_ userID: UUID) async throws {
			var chatGroupSocketsToClose: [UserSocket] = []
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				chatGroupSocketsToClose.append(
					contentsOf: request.application.websocketStorage.notificationSockets[userID] ?? []
				)
				request.application.websocketStorage.notificationSockets[userID] = nil
				for chatGroupSockets in request.application.websocketStorage.chatGroupSockets.values {
					let userchatGroupSockets = chatGroupSockets.filter { $0.userID == userID }
					if !userchatGroupSockets.isEmpty, let chatGroupID = userchatGroupSockets[0].chatGroupID {
						chatGroupSocketsToClose.append(contentsOf: userchatGroupSockets)
						let openSockets = chatGroupSockets.filter { $0.userID != userID }
						request.application.websocketStorage.chatGroupSockets[chatGroupID] = openSockets
					}
				}
			}
			for userGroupChatSocket in chatGroupSocketsToClose {
				try await userGroupChatSocket.socket.close().get()
			}
		}
	}
}
