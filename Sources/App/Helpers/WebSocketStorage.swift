import Vapor
import Fluent
import Redis

public struct UserSocket {
	let socketID: UUID
	let userID: UUID
	let socket: WebSocket
	let fezID: UUID?
	let htmlOutput: Bool
	
	init(userID: UUID, socket: WebSocket, fezID: UUID? = nil, htmlOutput: Bool = false) {
		self.userID = userID
		self.socket = socket
		socketID = UUID()
		self.fezID = fezID
		self.htmlOutput = htmlOutput
	}
}

extension Application {
 	/// This is where we store active WebSockets.
	var websocketStorage: WebSocketStorage {
		get {
			guard let result = self.storage[WebSocketStorageKey.self] else {
				return WebSocketStorage()
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
		var notificationSockets: [UUID : [UserSocket]] = [:]
		// Stored by fezID, so fezID : [UserSocket]
		var fezSockets: [UUID : [UserSocket]] = [:]
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
	
	public struct WebSocketStorage {
		let request: Request
		
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
	
// MARK: Fez Sockets
		func getFezSockets(_ fezID: UUID) -> [UserSocket] {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			let cacheResult = cacheLock.withLock { () -> [UserSocket] in 
				return request.application.websocketStorage.fezSockets[fezID] ?? []
			}
			return cacheResult
		}
	
		func storeFezSocket(_ ws: UserSocket) throws {
			guard let fezID = ws.fezID else { 
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.fezSockets[fezID] ?? []
				sockets.append(ws)
				request.application.websocketStorage.fezSockets[fezID] = sockets
			}
		}
		
		func removeFezSocket(_ ws: UserSocket) throws  {
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			guard let fezID = ws.fezID else { 
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			cacheLock.withLock {
				var sockets = request.application.websocketStorage.fezSockets[fezID] ?? []
				if let index = sockets.firstIndex(where: { $0.socketID == ws.socketID }) {
					sockets.remove(at: index)
					request.application.websocketStorage.fezSockets[fezID] = sockets
				}
			}
		}

// MARK: Logout
		func handleUserLogout(_ userID: UUID) throws {
			getSockets(userID).forEach { userSocket in
				_ = userSocket.socket.close()
				removeSocket(userSocket)
			}
			let cacheLock = request.application.locks.lock(for: Application.WebSocketStorageLockKey.self)
			try cacheLock.withLock {
				for socketArray in request.application.websocketStorage.fezSockets.values {
					for userSocket in socketArray {
						if userSocket.userID == userID {
							_ = userSocket.socket.close()
							try removeFezSocket(userSocket)
						}
					}
				}
			}
		}
	}
}
