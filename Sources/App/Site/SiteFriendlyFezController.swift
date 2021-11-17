import Vapor
import Crypto
import FluentSQL

// Form data from the Create/Update Fez form
struct CreateFezPostFormContent: Codable {
	var subject: String
	var location: String
	var eventtype: String
	var starttime: String
	var duration: Int
	var minimum: Int
	var maximum: Int
	var postText: String
}

struct FezCreateUpdatePageContext : Encodable {
	var trunk: TrunkContext
	var fez: FezData?
	var pageTitle: String
	var fezTitle: String = ""
	var fezLocation: String = ""
	var fezType: String = ""
	var startTime: Date?
	var minutes: Int = 0
	var minPeople: Int = 0
	var maxPeople: Int = 0
	var info: String = ""
	var formAction: String
	var submitButtonTitle: String = "Create"

	init(_ req: Request, fezToUpdate: FezData? = nil) throws {
		if let fez = fezToUpdate {
			trunk = .init(req, title: "Update Looking For Group", tab: .none)
			self.fez = fezToUpdate
			pageTitle = "Update Looking For Group"
			fezTitle = fez.title
			fezLocation = fez.location ?? ""
			fezType = fez.fezType.rawValue
			startTime = fez.startTime
			if let start = fez.startTime, let end = fez.endTime {
				minutes = Int(end.timeIntervalSince(start) / 60 + 0.01)		// should be 30, 60, 90, etc.
			}
			minPeople = fez.minParticipants
			maxPeople = fez.maxParticipants
			info = fez.info
			formAction = "/fez/\(fez.fezID)/update"
			submitButtonTitle = "Update"
		}
		else {
			trunk = .init(req, title: "New Looking For Group", tab: .none)
			pageTitle = "Create a New LFG"
			formAction = "/fez/create"
			minPeople = 2
			maxPeople = 2
		}
	}
	
	// Builds a Create Fez page for a fez, prefilled to play the indicated boardgame.
	// If `game` is an expansion set, you can optionally pass the baseGame in as well. 
	init(_ req: Request, forGame game: BoardgameData, baseGame: BoardgameData? = nil) {
		trunk = .init(req, title: "New LFG", tab: .none)
		pageTitle = "Create LFG to play a Boardgame"
		fezTitle = "Play \(game.gameName)"
		fezLocation = "Dining Room, Deck 3 Aft"
		fezType = "gaming"
		minutes = game.avgPlayingTime ?? game.minPlayingTime ?? game.maxPlayingTime ?? 0
		minPeople = game.minPlayers ?? 2
		maxPeople = game.maxPlayers ?? 2
		let copyText = game.numCopies == 1 ? "1 copy" : "\(game.numCopies) copies"
		info = "Play a board game! We'll be playing \"\(game.gameName)\".\n\nRemember, LFG is not a game reservation service. The game library has \(copyText) of this game."
		if let baseGame = baseGame {
			let baseGameCopyText = baseGame.numCopies == 1 ? "1 copy" : "\(baseGame.numCopies) copies"
			info.append("\n\n\(game.gameName) is an expansion pack for \(baseGame.gameName). You'll need to check this out of the library too. The game library has \(baseGameCopyText) of the base game.")
		}
		formAction = "/fez/create"
		submitButtonTitle = "Create"
	}
}
	


struct SiteFriendlyFezController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		let globalRoutes = getGlobalRoutes(app).grouped("fez").grouped(DisabledSiteSectionMiddleware(feature: .friendlyfez))
        globalRoutes.get("", use: fezRootPageHandler)
        globalRoutes.get("joined", use: joinedFezPageHandler)
        globalRoutes.get("owned", use: ownedFezPageHandler)
        globalRoutes.get("", fezIDParam, use: singleFezPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("fez").grouped(DisabledSiteSectionMiddleware(feature: .friendlyfez))
        privateRoutes.get("create", use: fezCreatePageHandler)
        privateRoutes.get(fezIDParam, "update", use: fezUpdatePageHandler)
        privateRoutes.get(fezIDParam, "edit", use: fezUpdatePageHandler)
        privateRoutes.post("create", use: fezCreateOrUpdatePostHandler)
        privateRoutes.post(fezIDParam, "update", use: fezCreateOrUpdatePostHandler)
        
        privateRoutes.post(fezIDParam, "join", use: fezJoinPostHandler)
        privateRoutes.post(fezIDParam, "leave", use: fezLeavePostHandler)
        privateRoutes.post(fezIDParam, "post", use: fezThreadPostHandler)
        privateRoutes.post(fezIDParam, "cancel", use: fezCancelPostHandler)
		privateRoutes.get("report", fezIDParam, use: fezReportPageHandler)
		privateRoutes.post("report", fezIDParam, use: fezReportPostHandler)
		privateRoutes.get(fezIDParam, "members", use: fezMembersPageHandler)
        privateRoutes.post(fezIDParam, "members", "add", userIDParam, use: fezAddUserPostHandler)
        privateRoutes.post(fezIDParam, "members", "remove", userIDParam, use: fezRemoveUserPostHandler)
		
		privateRoutes.webSocket(fezIDParam, "socket", onUpgrade: createFezSocket) 

		// Mods only
		privateRoutes.post(fezIDParam, "delete", use: fezDeleteHandler)
		privateRoutes.delete(fezIDParam, use: fezDeleteHandler)
	}
	
// MARK: - FriendlyFez

	enum FezTab: String, Codable {
		case find, joined, owned
	}

	// GET /fez
	// Shows the root Fez page, with a list of all fezzes.
	func fezRootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/open").throwingFlatMap { response in
			let fezzes = try response.content.decode([FezData].self)
			struct FezRootPageContext : Encodable {
				var trunk: TrunkContext
				var fezzes: [FezData]
				var tab: FezTab
				var typeSelection: String
				var daySelection: Int?
				
				init(_ req: Request, fezzes: [FezData]) throws {
					trunk = .init(req, title: "Looking For Group", tab: .none)
					self.fezzes = fezzes
					tab = .find
					typeSelection = req.query[String.self, at: "type"] ?? "all"
					daySelection = req.query[Int.self, at: "cruiseday"]
				}
			}
			let ctx = try FezRootPageContext(req, fezzes: fezzes)
			return req.view.render("Fez/fezRoot", ctx)
		}
	}
	
	// GET /fez/joined
	//
	// Shows the Joined Fezzes page.
	func joinedFezPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/joined?excludetype=closed").throwingFlatMap { response in
			let fezzes = try response.content.decode([FezData].self)
			struct JoinedFezPageContext : Encodable {
				var trunk: TrunkContext
				var fezzes: [FezData]
				var tab: FezTab
				
				init(_ req: Request, fezzes: [FezData]) throws {
					trunk = .init(req, title: "LFG Joined Groups", tab: .none)
					self.fezzes = fezzes
					tab = .joined
				}
			}
			let ctx = try JoinedFezPageContext(req, fezzes: fezzes)
			return req.view.render("Fez/fezJoined", ctx)
		}
	}
	
	// GET /fez/owned
	//
	// Shows the Owned Fezzes page. These are the Fezzes a user has created.
	func ownedFezPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/owner?excludetype=closed").throwingFlatMap { response in
			let fezzes = try response.content.decode([FezData].self)
			struct OwnedFezPageContext : Encodable {
				var trunk: TrunkContext
				var fezzes: [FezData]
				var tab: FezTab
				
				init(_ req: Request, fezzes: [FezData]) throws {
					trunk = .init(req, title: "LFGs Created By You", tab: .none)
					self.fezzes = fezzes
					tab = .owned
				}
			}
			let ctx = try OwnedFezPageContext(req, fezzes: fezzes)
			return req.view.render("Fez/fezOwned", ctx)
		}
	}
	
    
    // GET /fez/create
    //
    // Shows the Create New Friendly Fez page
    func fezCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		let ctx = try FezCreateUpdatePageContext(req)
		return req.view.render("Fez/fezCreate", ctx)
    }

	// GET `/fez/ID/update`
	// GET `/fez/ID/edit`
	//
	// Shows the Update Friendly Fez page.
    func fezUpdatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid fez ID"
    	}
		return apiQuery(req, endpoint: "/fez/\(fezID)").throwingFlatMap { response in
			let fez = try response.content.decode(FezData.self)
			let ctx = try FezCreateUpdatePageContext(req, fezToUpdate: fez)
			return req.view.render("Fez/fezCreate", ctx)
		}
    }
    
    // POST /fez/create
    // POST /fez/ID/update
    // Handles the POST from either the Create Or Update Fez page
    func fezCreateOrUpdatePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		let postStruct = try req.content.decode(CreateFezPostFormContent.self)
		var fezType: FezType
		switch postStruct.eventtype {
			case "activity": fezType = .activity
			case "dining": fezType = .dining
			case "gaming": fezType = .gaming
			case "meetup": fezType = .meetup
			case "music": fezType = .music
			case "ashore": fezType = .shore
			default: fezType = .other
		}
		guard let startTime = dateFromW3DatetimeString(postStruct.starttime) else {
			throw Abort(.badRequest, reason: "Couldn't parse start time")
		}
		let endTime = startTime.addingTimeInterval(TimeInterval(postStruct.duration) * 60.0)
		let fezContentData = FezContentData(fezType: fezType, 
				title: postStruct.subject, 
				info: postStruct.postText, 
				startTime: startTime, 
				endTime: endTime, 
				location: postStruct.location, 
				minCapacity: postStruct.minimum,
				maxCapacity: postStruct.maximum, 
				initialUsers: [])
		var path = "/fez/create"
		if let updatingFezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() {
			path = "/fez/\(updatingFezID)/update"
		}		
		return apiQuery(req, endpoint: path, method: .POST, beforeSend: { req throws in
			try req.content.encode(fezContentData)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
    }
    
    // GET /fez/ID
    // 
    // Shows a single Fez.
    func singleFezPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid fez ID"
    	}
		return apiQuery(req, endpoint: "/fez/\(fezID)").throwingFlatMap { response in
			let fez = try response.content.decode(FezData.self)
			struct FezPageContext : Encodable {
				var trunk: TrunkContext
				var fez: FezData
    			var oldPosts: [SocketFezPostData]
    			var showDivider: Bool
    			var newPosts: [SocketFezPostData]
     			var post: MessagePostContext
				
				init(_ req: Request, fez: FezData) throws {
					trunk = .init(req, title: "LFG", tab: .none)
					self.fez = fez
    				oldPosts = []
    				newPosts = []
    				showDivider = false
    				post = .init(forType: .fezPost(fez))
    				if let members = fez.members, let posts = members.posts {
						let participantDictionary = members.participants.reduce(into: [:]) { $0[$1.userID] = $1 }
						for index in 0..<posts.count {
							let post = posts[index]
							if index < members.readCount {
								if let author = participantDictionary[post.authorID] {
									oldPosts.append(SocketFezPostData(post: post, author: author))
								}
							}
							else {
								if let author = participantDictionary[post.authorID] {
									newPosts.append(SocketFezPostData(post: post, author: author))
								}
							}
						} 
						self.showDivider = oldPosts.count > 0 && newPosts.count > 0
					}
				}
			}
			let ctx = try FezPageContext(req, fez: fez)
			return req.view.render("Fez/singleFez", ctx)
		}
	}
	
	// WS /fez/:fez_ID/socket
	//
	// Opens a WebSocket that receives updates on the given Fez. This websocket is intended for use by the
	// web client and updates are in the form of HTML fragments.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createFezSocket(_ req: Request, _ ws: WebSocket) {
		guard let user = try? req.auth.require(UserCacheData.self) else {
			_ = ws.close()
			return
		}
		_ = FriendlyFez.findFromParameter(fezIDParam, on: req).map { fez in
			guard fez.participantArray.contains(user.userID), let fezID = try? fez.requireID() else {
				_ = ws.close()
				return
			}
			let userSocket = UserSocket(userID: user.userID, socket: ws, fezID: fezID, htmlOutput: true)
			try? req.webSocketStore.storeFezSocket(userSocket)

			ws.onClose.whenComplete { result in
				try? req.webSocketStore.removeFezSocket(userSocket)
			}
		}
	}
	
	// POST /fez/ID/post
	//
	// Post a message in a fez.
	func fezThreadPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = PostContentData(text: postStruct.postText ?? "", images: [])
		return apiQuery(req, endpoint: "/fez/\(fezID)/post", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			return Response(status: .created)
		}
	}
	
	// POST /fez/ID/join
	//
	// Joins a fez.
	func fezJoinPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/join", method: .POST).flatMapThrowing { response in
			return Response(status: .created)
    	}
	}
	
	// POST /fez/ID/leave
	//
	// Leaves a fez.
	func fezLeavePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/unjoin", method: .POST).flatMapThrowing { response in
			return Response(status: .created)
    	}
	}
	
	// POST /fez/ID/cancel
	//
	// Cancels a fez. Owner only.
	func fezCancelPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/cancel", method: .POST).flatMapThrowing { response in
			return Response(status: .created)
    	}
	}
	
	// GET /fez/ID/members
	//
	// Allows the owner of a fez to add/remove members.
	func fezMembersPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid fez ID"
    	}
		return apiQuery(req, endpoint: "/fez/\(fezID)").throwingFlatMap { response in
			let fez = try response.content.decode(FezData.self)
			let ctx = try FezCreateUpdatePageContext(req, fezToUpdate: fez)
			return req.view.render("Fez/fezManageMembers", ctx)
		}
    }
		
	// POST /fez/fez_ID/members/add/user_ID
	//
	// Allows a fez owner to add a user to their fez.
	func fezAddUserPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/user/\(userID)/add", method: .POST).flatMapThrowing { response in
			return .created
    	}
	}
	
	// POST /fez/fez_ID/members/remove/user_ID
	//
	// Allows a fez owner to remove a user from their fez.
	func fezRemoveUserPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/user/\(userID)/remove", method: .POST).flatMapThrowing { response in
			return .created
    	}
	}
	
	// GET /fez/report/ID
	//
	// Shows the page for reporting on a fezzes' content.
	func fezReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let ctx = try ReportPageContext(req, fezID: fezID)
    	return req.view.render("reportCreate", ctx)
    }
    
    // POST /fez/report/ID
    //
    // Submits a report on a fez.
	func fezReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/fez/\(fezID)/report", method: .POST, beforeSend: { req throws in
			try req.content.encode(postStruct)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
    }	
    
    // POST /fez/ID/delete
    // DELETE /fez/ID
    //
	// Deletes a fez. Moderators only at the moment--owners may be able to delete, eventually.
    func fezDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let fez = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "While deleting fez: Invalid fez ID"
    	}
    	return apiQuery(req, endpoint: "/fez/\(fez)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
    
//	Title							 Starts: Time
//	by: Owner						1 post, 1 new
// 	Gaming							Duration: 1hr
//
//	Location				 9 of 10 participants
//  Expands to show Info here
   
//	Title							    Time, 1hr
//	by: Owner				 9 of 10 participants		OR: Full, 2 on waitlist
// 	Gaming							1 post, 1 new 			
//
//	Location				 		
//  Expands to show Info here
//									Report   Join 

// Inside the fez you can Leave, Post, DeletePost, Report, 
// Creator can Cancel, Update, AddUser, RemoveUser
    
}
