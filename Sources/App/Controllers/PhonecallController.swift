import Vapor
import Crypto
import FluentSQL
import Fluent

actor ActivePhoneCalls {
	static let shared = ActivePhoneCalls()
	
	struct PhoneCall {
		var caller: UUID
		var callee: UUID
		var callID: UUID
		var callerSocket: WebSocket
		var calleeSocket: WebSocket?		
	}
	var calls: [PhoneCall] = []
	
	func newPhoneCall(caller: UUID, callee: UUID, callID: UUID, callerSocket: WebSocket) throws {
		guard currentCall(for: caller) == nil else {
			throw Abort(.badRequest, reason: "Caller already on a phone call.")
		}
		guard currentCall(for: callee) == nil else {
			throw Abort(.badRequest, reason: "User is unavailable.")
		}
		calls.append(PhoneCall(caller: caller, callee: callee, callID: callID, callerSocket: callerSocket, calleeSocket: nil))
	}
	
	@discardableResult func endPhoneCall(callID: UUID) -> Bool {
		var closedSomething = false
		if let call = calls.first(where: { $0.callID == callID }) {
			_ = call.callerSocket.close()
			_ = call.calleeSocket?.close()
			closedSomething = true
		}
		calls.removeAll{ $0.callID == callID }
		return closedSomething
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

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		// convenience route group for all /api/v3/phone endpoints
		let phoneRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .phone)).grouped("api", "v3", "phone")
	   
		// Open access routes
				
		// endpoints available only when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: phoneRoutes)
//		tokenCacheAuthGroup.get("initiate", userIDParam, use: initiateCallHandler)
		tokenCacheAuthGroup.webSocket("socket", "initiate", phonecallParam, "to", userIDParam, 
				shouldUpgrade: shouldCreatePhoneSocket, onUpgrade: createPhoneSocket)
		tokenCacheAuthGroup.webSocket("socket", "answer", phonecallParam,
				shouldUpgrade: shouldAnswerPhoneSocket, onUpgrade: answerPhoneSocket)
				
		tokenCacheAuthGroup.post("decline", phonecallParam, use: declinePhoneCall)
	}
	
	// GET /seamail/:seamail_ID/socket
	func shouldCreatePhoneSocket(_ req: Request) async throws -> HTTPHeaders? {
  		guard let paramVal = req.parameters.get(userIDParam.paramString), let calleeID = UUID(uuidString: paramVal) else {
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
		
		// Make sure we can notify the callee
		let callerNotificationSockets = req.webSocketStore.getSockets(calleeID)
		guard !callerNotificationSockets.isEmpty else {
			req.logger.log(level: .notice, "Attempt to call user with no notification socket.")
			throw Abort(.notFound, reason: "User unavailable.")
		}
		
		return HTTPHeaders()
	}
	
	// WS /api/v3/phone/socket/initiate/:call_ID/to/:user_ID
	//
	func createPhoneSocket(_ req: Request, _ ws: WebSocket) async {
		req.logger.log(level: .notice, "Creating phone socket.")
		guard let caller = try? req.auth.require(UserCacheData.self), 
				let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam),
				let userParam = req.parameters.get(userIDParam.paramString), let calleeID = UUID(uuidString: userParam),
				let _ = try? req.userCache.getHeader(calleeID) else {
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
		let msgStruct = SocketNotificationData(callID: callID, caller: caller.makeHeader())
		if let jsonData = try? JSONEncoder().encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8) {
			calleeNotificationSockets.forEach { userSocket in
				req.logger.log(level: .notice, "Sending incoming phonecall to callee.")
				userSocket.socket.send(jsonDataStr)
			}
		}
		else {
			try? await ws.close()
			return
		}
		
		// Create a new call object
		try? await ActivePhoneCalls.shared.newPhoneCall(caller: caller.userID, callee: calleeID, callID: callID, callerSocket: ws)
		ws.onClose.whenComplete { result in
			Task {
				let callClosed = await ActivePhoneCalls.shared.endPhoneCall(callID: callID)
				if callClosed {
					req.logger.info("Phone call \(callID) ended.")
				}
			}
		}
		ws.onBinary { ws, binary in
			Task {
				if let call = await ActivePhoneCalls.shared.getCall(withID: callID), let calleeSocket = call.calleeSocket {
					try? await calleeSocket.send(Array<UInt8>(buffer: binary))
				}
			}			
		}
	}

	// WS /api/v3/phone/socket/answer/:call_ID
	//
	func shouldAnswerPhoneSocket(_ req: Request) async throws -> HTTPHeaders? {
		let callee = try req.auth.require(UserCacheData.self)
		guard let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam) else {
			throw Abort(.badRequest, reason: "Request parameter call_ID is missing.")
		}
		guard let call = await ActivePhoneCalls.shared.getCall(withID: callID), call.callee == callee.userID else {
			throw Abort(.badRequest, reason: "Couldn't find phone call.")
		}

		return HTTPHeaders()
	}
	
	// WS /api/v3/phone/socket/initiate/:call_ID/to/:user_ID
	//
	func answerPhoneSocket(_ req: Request, _ ws: WebSocket) async {
		guard let callee = try? req.auth.require(UserCacheData.self),
				let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam) else {
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
		if let jsonData = try? JSONEncoder().encode(PhoneSocketStartData()) {
			try? await call.callerSocket.send(raw: jsonData, opcode: .binary)
			try? await call.calleeSocket?.send(raw: jsonData, opcode: .binary)
		}
		
		ws.onClose.whenComplete { result in
			Task {
				let callClosed = await ActivePhoneCalls.shared.endPhoneCall(callID: callID)
				if callClosed {
					req.logger.info("Phone call \(callID) ended.")
				}
			}
		}
		
		ws.onBinary { ws, binary in
			Task {
				if let call = await ActivePhoneCalls.shared.getCall(withID: callID) {
					try? await call.callerSocket.send(Array<UInt8>(buffer: binary))
				}
			}			
		}
	}
	
	// POST /api/v3/phone/socket/decline/:call_ID
	//
	func declinePhoneCall(_ req: Request) async throws -> HTTPStatus {
		guard let callee = try? req.auth.require(UserCacheData.self),
				let callParam = req.parameters.get(phonecallParam.paramString), let callID = UUID(uuidString: callParam) else {
			throw Abort(.badRequest, reason: "Request parameter call_ID is missing.")
		}
		guard let call = await ActivePhoneCalls.shared.getCall(withID: callID), call.callee == callee.userID else {
			throw Abort(.badRequest, reason: "No active call with this ID.")
		}
		let callClosed = await ActivePhoneCalls.shared.endPhoneCall(callID: callID)
		if callClosed {
			req.logger.info("Phone call \(callID) ended.")
		}
		return .ok
	}
}
