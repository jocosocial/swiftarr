import Fluent
import Redis
import Vapor

public struct UserSocket: Sendable {
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
	/// Stored by user, so userID : [UserSocket]
	var notificationSockets: WebSocketStorage {
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
	// Stored by fezID, so fezID : [UserSocket]
	var chatSockets: WebSocketStorage {
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
	actor WebSocketStorage {
		private var sockets: [UUID: [UserSocket]] = [:]

		// Gets the sockets for a single entity (currently: User or LFG). For users, this array returns sockets for all the 
		// devices the user is logged in from. For LFGs, it returns sockets for all users live-monitoring the LFG.
		func getSockets(_ forID: UUID) -> [UserSocket] {
			return sockets[forID] ?? []
		}

		// Gets the notification sockets for the given list of ids. Flatmaps each user's 
		func getSockets<T: Sequence>(idList: T) -> [UserSocket] where T.Element == UUID {
			return idList.flatMap { sockets[$0] ?? [] }
		}
		
		func hasSocket(forID: UUID) -> Bool {
			return (sockets[forID]?.count ?? 0) > 0
		}		

		// Send a message to all involved users with open websockets.
		// This logic used to be in APIRouteCollection.swift. But with the introduction of the
		// UserEventNotificationJob we needed this function in a non-Request context.
		func forwardToSockets(app: Application, idList: [UUID], type: NotificationType, info: String) -> Void {
			let socketeers = getSockets(idList: idList)
			if socketeers.count > 0 {
				app.logger.log(level: .info, "Socket: Sending \(type) msg to \(socketeers.count) client.")
				let msgStruct = SocketNotificationData(type, info: info, id: type.objectID())
				if let jsonData = try? JSONEncoder().encode(msgStruct),
					let jsonDataStr = String(data: jsonData, encoding: .utf8)
				{
					socketeers.forEach { socket in
						socket.socket.send(jsonDataStr)
					}
				}
			}
		}
		
		// Adds the given socket to the given UUID's socket list.
		func storeSocket(_ socket: UserSocket, withID: UUID) {
			sockets[withID, default: []].append(socket)
		}
		
		func removeSocket(_ socket: UserSocket, fromID: UUID) {
			var socketArray = sockets[fromID] ?? []
			if let index = socketArray.firstIndex(where: { $0.socketID == socket.socketID }) {
				socketArray.remove(at: index)
				sockets[fromID] = socketArray
			}
		}
		
		func handleUserLogout(_ userID: UUID, isUserIndexed: Bool) async {
			if isUserIndexed {
				let socketList = sockets[userID] ?? []
				for socket in socketList {
					try? await socket.socket.close().get()
				}
			}
			else {
				var socketsToClose: [UserSocket] = []
				for socketArray in sockets.values {
					let userSockets = socketArray.filter { $0.userID == userID }
					if !userSockets.isEmpty, let chatID = userSockets[0].fezID {
						socketsToClose.append(contentsOf: userSockets)
						let openSockets = socketArray.filter { $0.userID != userID }
						sockets[chatID] = openSockets
					}
				}
				for userSocket in socketsToClose {
					try? await userSocket.socket.close().get()
				}
			}
		}
	}

	/// Storage key used by Vapor's Services API. Used by UserCache to access its cache data.
	struct WebSocketStorageKey: StorageKey, Sendable {
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
		
		enum SocketType {
			case userNotification
			case chat
		}

		public init(request: Request) {
			self.request = request
		}

		// MARK: Notification Sockets
		func userHasSocket(_ userID: UUID) async -> Bool {
			return await request.application.notificationSockets.hasSocket(forID: userID)
		}
		
		func getSockets(_ id: UUID) async -> [UserSocket] {
			return await request.application.notificationSockets.getSockets(id)
		}

		func getSockets(type: SocketType, _ forIDs: Array<UUID>) async -> [UserSocket] {
			return await request.application.notificationSockets.getSockets(idList: forIDs)
		}

		func storeSocket(_ ws: UserSocket) async {
			await request.application.notificationSockets.storeSocket(ws, withID: ws.userID)
		}

		func removeSocket(_ ws: UserSocket) async {
			await request.application.notificationSockets.removeSocket(ws, fromID: ws.userID)
		}

		// MARK: Chat Sockets
		func getChatSockets(_ chatID: UUID) async -> [UserSocket] {
			return await request.application.chatSockets.getSockets(chatID)
		}

		func storeChatSocket(_ ws: UserSocket) async throws {
			guard let chatID = ws.fezID else {
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			await request.application.chatSockets.storeSocket(ws, withID: chatID)
		}

		func removeChatSocket(_ ws: UserSocket) throws {
			guard let chatID = ws.fezID else {
				throw Abort(.badRequest, reason: "WebSocket for a conversation needs the conversation ID")
			}
			let socketStore = request.application.chatSockets
			Task {
				await socketStore.removeSocket(ws, fromID: chatID)
			}
		}

		// MARK: Logout
		
		// This case is only used when we do an API logout, removing the user token; this logs the out of all sessions.
		// The web UI has a different logout case used when logging out of the current browser session.
		func handleUserLogout(_ userID: UUID) async throws {
			// This closes the user's notification sockets 
			await request.application.notificationSockets.handleUserLogout(userID, isUserIndexed: true)
			await request.application.chatSockets.handleUserLogout(userID, isUserIndexed: false)
		}
	}
}
