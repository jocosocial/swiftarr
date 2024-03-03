import Crypto
import Fluent
import FluentSQL
import Vapor

// Active phone calls the server is aware of. For calls where each client opens a WS to the server and the server
// forwards audio between sockets, the call object is opened when the caller initiates (tells us they're trying to start a call),
// and ends when the call hangs up (by either party). For calls that send audio data phone-to-phone, the call object is released
// when the callee either accepts or declines the call.
actor ActivePhoneCalls {
	static let shared = ActivePhoneCalls()

	struct PhoneCall {
		var caller: UUID
		var callee: UUID
		var callID: UUID
		var callerSocket: WebSocket?
		var calleeSocket: WebSocket?
		var calleeNotificationSockets: [WebSocket]
	}
	var calls: [PhoneCall] = []

	func newPhoneCall(
		caller: UserHeader,
		callee: UserHeader,
		callID: UUID,
		callerSocket: WebSocket?,
		notifySockets: [WebSocket]
	) throws {
		// Not sure about this--what if the user is on 2 devices?
		guard currentCall(for: caller.userID) == nil else {
			throw Abort(.badRequest, reason: "Caller already on a phone call.")
		}
		// This bit stays until we add multi-call management.
		guard currentCall(for: callee.userID) == nil else {
			throw Abort(.badRequest, reason: "User is unavailable.")
		}
		calls.append(
			PhoneCall(
				caller: caller.userID,
				callee: callee.userID,
				callID: callID,
				callerSocket: callerSocket,
				calleeSocket: nil,
				calleeNotificationSockets: notifySockets
			)
		)
		//		req.logger.info("Call \(callID) initiated by \(caller.username) calling \(callee.username)")
	}

	func endPhoneCall(callID: UUID) {
		if let call = calls.first(where: { $0.callID == callID }) {
			_ = call.callerSocket?.close()
			_ = call.calleeSocket?.close()
		}
		calls.removeAll { $0.callID == callID }
	}

	func currentCall(for userID: UUID) -> PhoneCall? {
		return calls.first { $0.caller == userID || $0.callee == userID }
	}

	func getCall(withID: UUID) -> PhoneCall? {
		return calls.first { $0.callID == withID }
	}

	func save(call: PhoneCall) {
		calls.removeAll { $0.callID == call.callID }
		calls.append(call)
	}
}

/// The collection of `/api/v3/phone/*` route endpoints and handler functions related to phone call management..
struct PhonecallController: APIRouteCollection {
	static let logger = Logger(label: "app.phonecall")

	var encoder: JSONEncoder {
		let enc = JSONEncoder()
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
		formatter.calendar = Calendar(identifier: .iso8601)
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		enc.dateEncodingStrategy = .formatted(formatter)
		return enc
	}

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		// convenience route group for all /api/v3/phone endpoints
		let phoneRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .phone)).grouped("api", "v3", "phone")

		// Open access routes

		// endpoints available only when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: phoneRoutes)
		tokenCacheAuthGroup.webSocket(
			"socket",
			"initiate",
			phonecallParam,
			"to",
			userIDParam,
			shouldUpgrade: shouldCreatePhoneSocket,
			onUpgrade: createPhoneSocket
		)
		tokenCacheAuthGroup.webSocket(
			"socket",
			"answer",
			phonecallParam,
			shouldUpgrade: shouldAnswerPhoneSocket,
			onUpgrade: answerPhoneSocket
		)

		tokenCacheAuthGroup.post("answer", phonecallParam, use: answerPhoneCall)
		tokenCacheAuthGroup.post("decline", phonecallParam, use: declinePhoneCall)

		// Routes only used for direct-connect phone sessions
		let directPhoneAuthGroup = tokenCacheAuthGroup.grouped(DisabledAPISectionMiddleware(feature: .directphone))
		directPhoneAuthGroup.post("initiate", phonecallParam, "to", userIDParam, use: initiateCallHandler)
	}

	/// `POST /api/v3/phone/initiate/:call_id/to/:user_id`
	///
	/// The requester is trying to start a phone call to the given user. Notify the target user of the incoming phone call via their notification socket and provide
	/// the IP address(es) of the caller. The callee is then expected to open a socket to the caller for moving audio.
	///
	/// - Parameter callID: in URL path. Caller-provided UUID for this call. Callee needs to send this to caller to verify the socket is for the correct call.
	/// - Parameter userID: The userID of the user to call.
	/// - Throws: BadRequest if malformed. notFound if user can't be notified of call.
	/// - Returns: 200 OK on success
	func initiateCallHandler(_ req: Request) async throws -> HTTPStatus {
		guard let calleeParam = req.parameters.get(userIDParam.paramString),
			let calleeID = UUID(uuidString: calleeParam),
			let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam)
		else {
			throw Abort(.badRequest, reason: "Request parameter missing.")
		}
		let caller = try req.auth.require(UserCacheData.self)
		guard let callee = req.userCache.getUser(calleeID) else {
			throw Abort(.badRequest, reason: "Couldn't find user to call.")
		}
		if callee.getMutes().contains(caller.userID) || callee.getBlocks().contains(caller.userID) {
			throw Abort(.badRequest, reason: "Cannot call this user.")
		}
		guard let _ = try await UserFavorite.query(on: req.db).filter(\.$user.$id == callee.userID)
				.filter(\.$favorite.$id == caller.userID).first() else {
			throw Abort(.badRequest, reason: "Cannot call a user who has not made you a favorite user.")
		}

		let calleeNotificationSockets = req.webSocketStore.getSockets(calleeID)
		guard !calleeNotificationSockets.isEmpty else {
			req.logger.log(level: .notice, "Attempt to call user with no notification socket.")
			throw Abort(.badRequest, reason: "User unavailable.")
		}

		let callerDeviceAddr = try ValidatingJSONDecoder().decode(PhoneSocketServerAddress.self, fromBodyOf: req)
		guard callerDeviceAddr.ipV6Addr != nil || callerDeviceAddr.ipV4Addr != nil else {
			throw Abort(.badRequest, reason: "Cannot call this user.")
		}

		// Save the incoming call
		let notificationSockets = calleeNotificationSockets.map { $0.socket }
		try? await ActivePhoneCalls.shared.newPhoneCall(
			caller: caller.makeHeader(),
			callee: callee.makeHeader(),
			callID: callID,
			callerSocket: nil,
			notifySockets: notificationSockets
		)

		// Send incoming call notification to all of the callee's devices
		let msgStruct = SocketNotificationData(
			callID: callID,
			caller: caller.makeHeader(),
			callerAddr: callerDeviceAddr
		)
		if let jsonData = try? encoder.encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8) {
			calleeNotificationSockets.forEach { userSocket in
				req.logger.log(level: .notice, "Sending incoming phonecall to callee.")
				userSocket.socket.send(jsonDataStr)
			}
		}
		return .ok
	}

	/// `GET /api/v3/phone/socket/initiate/:call_id/to/:user_id`
	///
	/// The requester is trying to start a phone call to the given user. Notify the target user of the incoming phone call via their notification socket and save the
	/// caller socket. The callee should open a phone socket to the server using `answerPhoneSocket` at which point the server will start forwarding websocket
	/// packets between the caller and callee sockets.
	///
	/// This is the server-mediated phone call path.
	///
	/// - Parameter callID: in URL path. Caller-provided UUID for this call. Callee needs to send this to caller to verify the socket is for the correct call.
	/// - Parameter userID: The userID of the user to call.
	/// - Throws: BadRequest if malformed. notFound if user can't be notified of call.
	/// - Returns: 200 OK on success
	func shouldCreatePhoneSocket(_ req: Request) async throws -> HTTPHeaders? {
		guard let paramVal = req.parameters.get(userIDParam.paramString), let calleeID = UUID(uuidString: paramVal)
		else {
			throw Abort(.badRequest, reason: "Request parameter user_ID is missing.")
		}

		// Disallow if the callee mutes or blocks the caller
		let caller = try req.auth.require(UserCacheData.self)
		guard let callee = req.userCache.getUser(calleeID) else {
			throw Abort(.badRequest, reason: "Couldn't find user to call.")
		}
		if callee.getMutes().contains(caller.userID) || callee.getBlocks().contains(caller.userID) {
			throw Abort(.badRequest, reason: "Cannot call this user.")
		}
		guard let _ = try await UserFavorite.query(on: req.db).filter(\.$user.$id == callee.userID)
				.filter(\.$favorite.$id == caller.userID).first() else {
			throw Abort(.badRequest, reason: "Cannot call a user who has not made you a favorite user.")
		}

		// Make sure we can notify the callee
		let callerNotificationSockets = req.webSocketStore.getSockets(calleeID)
		guard !callerNotificationSockets.isEmpty else {
			req.logger.log(level: .notice, "Attempt to call user with no notification socket.")
			throw Abort(.notFound, reason: "User unavailable.")
		}

		return HTTPHeaders()
	}

	/// `WS /api/v3/phone/socket/initiate/:call_id/to/:user_id`
	///
	/// The requester is trying to start a phone call to the given user. Notify the target user of the incoming phone call via their notification socket and save the
	/// caller socket. The callee should open a phone socket to the server using `answerPhoneSocket` at which point the server will start forwarding websocket
	/// packets between the caller and callee sockets.
	///
	/// This is the server-mediated phone call path.
	///
	/// - Parameter callID: in URL path. Caller-provided UUID for this call. Callee needs to send this to caller to verify the socket is for the correct call.
	/// - Parameter userID: The userID of the user to call.
	/// - Throws: BadRequest if malformed. notFound if user can't be notified of call.
	/// - Returns: 200 OK on success
	func createPhoneSocket(_ req: Request, _ ws: WebSocket) async {
		req.logger.log(level: .notice, "Creating phone socket.")
		guard let caller = try? req.auth.require(UserCacheData.self),
			let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam),
			let userParam = req.parameters.get(userIDParam.paramString), let calleeID = UUID(uuidString: userParam),
			let callee = try? req.userCache.getHeader(calleeID)
		else {
			try? await ws.close()
			return
		}

		// Double-check we can notify the callee
		let calleeNotificationSockets = req.webSocketStore.getSockets(calleeID)
		guard !calleeNotificationSockets.isEmpty else {
			req.logger.log(level: .notice, "All of a sudden, no callee notification socket.")
			try? await ws.close()
			return
		}

		// Send incoming call notification to all of the callee's devices
		let msgStruct = SocketNotificationData(callID: callID, caller: caller.makeHeader(), callerAddr: nil)
		if let jsonData = try? encoder.encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8) {
			req.logger.log(level: .notice, "Sending incoming phonecall to callee's \(calleeNotificationSockets.count) devices.")
			calleeNotificationSockets.forEach { userSocket in
				userSocket.socket.send(jsonDataStr)
			}
		}
		else {
			try? await ws.close()
			return
		}

		// Create a new call object
		try? await ActivePhoneCalls.shared.newPhoneCall(
			caller: caller.makeHeader(),
			callee: callee,
			callID: callID,
			callerSocket: ws,
			notifySockets: calleeNotificationSockets.map { $0.socket }
		)

		// https://github.com/jocosocial/swiftarr/issues/253
		// https://github.com/vapor/websocket-kit/issues/139
		// https://github.com/vapor/websocket-kit/issues/140
		ws.eventLoop.execute {
			ws.onClose.whenComplete { result in
				endPhoneCall(callID: callID)
			}
			ws.onBinary { ws, binary in
				Task {
					if let call = await ActivePhoneCalls.shared.getCall(withID: callID),
						let calleeSocket = call.calleeSocket
					{
						try? await calleeSocket.send([UInt8](buffer: binary))
					}
				}
			}
		}
		
	}

	/// `GET /api/v3/phone/socket/answer/:call_id`
	///
	/// The requester is trying to answer an incoming phone call.  This is the server-mediated phone call path.
	///
	/// - Parameter callID: in URL path. Caller-provided UUID for this call. Callee needs to send this to caller to verify the socket is for the correct call.
	/// - Throws: BadRequest if malformed. NotFound if callID doesn't exist.
	/// - Returns: 200 OK on success
	func shouldAnswerPhoneSocket(_ req: Request) async throws -> HTTPHeaders? {
		let callee = try req.auth.require(UserCacheData.self)
		guard let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam)
		else {
			throw Abort(.badRequest, reason: "Request parameter call_ID is missing.")
		}
		guard let call = await ActivePhoneCalls.shared.getCall(withID: callID), call.callee == callee.userID else {
			throw Abort(.notFound, reason: "Couldn't find phone call.")
		}

		// Send 'already answered' to all the callee's devices, so they stop ringing
		let calleeNotificationSockets = req.webSocketStore.getSockets(call.callee)
		let msgStruct = SocketNotificationData(forCallAnswered: call.callID)
		if let jsonData = try? encoder.encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8) {
			calleeNotificationSockets.forEach { notificationSocket in
				notificationSocket.socket.send(jsonDataStr)
			}
		}
		return HTTPHeaders()
	}

	/// `WS /api/v3/phone/socket/answer/:call_id`
	///
	/// The requester is trying to answer an incoming phone call.  This is the server-mediated phone call path.
	///
	/// - Parameter callID: in URL path. Caller-provided UUID for this call. Callee needs to send this to caller to verify the socket is for the correct call.
	/// - Throws: BadRequest if malformed. NotFound if callID doesn't exist.
	/// - Returns: 200 OK on success
	func answerPhoneSocket(_ req: Request, _ ws: WebSocket) async {
		guard let callee = try? req.auth.require(UserCacheData.self),
			let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam)
		else {
			req.logger.log(level: .notice, "Couldn't open answer socket.")
			try? await ws.close()
			return
		}
		guard var call = await ActivePhoneCalls.shared.getCall(withID: callID), call.callee == callee.userID else {
			req.logger.log(level: .notice, "Couldn't open answer socket; couldn't find caller.")
			try? await ws.close()
			return
		}

		call.calleeSocket = ws
		await ActivePhoneCalls.shared.save(call: call)
		if let jsonData = try? encoder.encode(PhoneSocketStartData()) {
			try? await call.callerSocket?.send(raw: jsonData, opcode: .binary)
			try? await call.calleeSocket?.send(raw: jsonData, opcode: .binary)
		}

		// https://github.com/jocosocial/swiftarr/issues/253
		// https://github.com/vapor/websocket-kit/issues/139
		// https://github.com/vapor/websocket-kit/issues/140
		ws.eventLoop.execute {
			ws.onClose.whenComplete { result in
				endPhoneCall(callID: callID)
			}

			ws.onBinary { ws, binary in
				Task {
					if let call = await ActivePhoneCalls.shared.getCall(withID: callID) {
						try? await call.callerSocket?.send([UInt8](buffer: binary))
					}
				}
			}
		}
	}

	/// `POST /api/v3/phone/answer/:call_ID`
	///
	/// The answering party should call this when they answer the incoming call; this notifies other devices where that user is logged in to stop ringing. Only necessary
	/// for the direct-socket path.
	///
	/// - Parameter callID: in URL path. UUID for this call.
	/// - Throws: BadRequest if malformed. NotFound if callID doesn't exist.
	/// - Returns: 200 OK on success
	func answerPhoneCall(_ req: Request) async throws -> HTTPStatus {
		guard let callee = try? req.auth.require(UserCacheData.self),
			let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam)
		else {
			throw Abort(.badRequest, reason: "Request parameter call_ID is missing.")
		}
		// Send 'call answered' to all the callee's devices, so they stop ringing
		let calleeNotificationSockets = req.webSocketStore.getSockets(callee.userID)
		let msgStruct = SocketNotificationData(forCallAnswered: callID)
		if let jsonData = try? encoder.encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8) {
			calleeNotificationSockets.forEach { notificationSocket in
				notificationSocket.socket.send(jsonDataStr)
			}
		}
		if let call = await ActivePhoneCalls.shared.getCall(withID: callID),
			call.callerSocket == nil && call.calleeSocket == nil
		{
			await ActivePhoneCalls.shared.endPhoneCall(callID: callID)
		}
		return .ok
	}

	/// `POST /api/v3/phone/decline/:call_ID`
	///
	/// Either party may call this to end a server-mediated phone call. But, if you have an open socket for the call, it's easier to just close the socket--the server
	/// will detect this and close the other socket and clean up. Requester must be a party to the call.
	///
	/// This route is for when a phone call needs to be ended and the client does not have a socket connection. May be used for both direct and server-mediated calls.
	///
	/// - Parameter callID: in URL path. Caller-provided UUID for this call. Callee needs to send this to caller to verify the socket is for the correct call.
	/// - Throws: BadRequest if malformed. NotFound if callID doesn't exist.
	/// - Returns: 200 OK on success
	func declinePhoneCall(_ req: Request) async throws -> HTTPStatus {
		guard let _ = try? req.auth.require(UserCacheData.self),
			let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam)
		else {
			throw Abort(.badRequest, reason: "Request parameter call_ID is missing.")
		}
		// Tell the caller the call is declined. Only necessary for the direct-connect case.
		if let call = await ActivePhoneCalls.shared.getCall(withID: callID) {
			let callerSockets = req.webSocketStore.getSockets(call.caller)
			let msgStruct = SocketNotificationData(forCallEnded: callID)
			if let jsonData = try? encoder.encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8)
			{
				callerSockets.forEach { notificationSocket in
					notificationSocket.socket.send(jsonDataStr)
				}
			}
		}
		endPhoneCall(callID: callID)
		return .ok
	}

	// MARK: Utilities

	// Call this when a server-mediated phone call ends (either socket closes), or when a direct-connect phone call is declined.
	// Cleans up sockets, tells all callee devices the call is over (to ensure they leave the ringing state).
	func endPhoneCall(callID: UUID) {
		Task {
			guard let call = await ActivePhoneCalls.shared.getCall(withID: callID) else {
				return
			}
			// Send hangup to all the callee's devices, so they stop ringing
			let msgStruct = SocketNotificationData(forCallEnded: call.callID)
			if let jsonData = try? encoder.encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8)
			{
				call.calleeNotificationSockets.forEach { notificationSocket in
					if !notificationSocket.isClosed {
						notificationSocket.send(jsonDataStr)
					}
				}
			}
			// Remove the call object
			await ActivePhoneCalls.shared.endPhoneCall(callID: callID)
		}
	}
}
