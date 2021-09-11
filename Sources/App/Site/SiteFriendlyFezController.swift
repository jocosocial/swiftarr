import Vapor
import Crypto
import FluentSQL

// FezPostData, modified to be easier for Leaf
struct LeafFezPostData: Codable {
	var postID: Int
	var author: UserHeader
	var text: String
	var timestamp: Date
	
	init(post: FezPostData, author: UserHeader) {
		self.postID = post.postID
		self.author = author
		self.text = post.text
		self.timestamp = post.timestamp
	}
}

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
			trunk = .init(req, title: "Update FriendlyFez", tab: .none)
			pageTitle = "Update Friendly Fez"
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
			trunk = .init(req, title: "New FriendlyFez", tab: .none)
			pageTitle = "Create a New Friendly Fez"
			formAction = "/fez/create"
			minPeople = 2
			maxPeople = 2
		}
	}
}
	


struct SiteFriendlyFezController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .friendlyfez))
        globalRoutes.get("fez", use: fezRootPageHandler)
        globalRoutes.get("fez", "joined", use: joinedFezPageHandler)
        globalRoutes.get("fez", "owned", use: ownedFezPageHandler)
        globalRoutes.get("fez", fezIDParam, use: singleFezPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .friendlyfez))
        privateRoutes.get("fez", "create", use: fezCreatePageHandler)
        privateRoutes.get("fez", fezIDParam, "update", use: fezUpdatePageHandler)
        privateRoutes.get("fez", fezIDParam, "edit", use: fezUpdatePageHandler)
        privateRoutes.post("fez", "create", use: fezCreateOrUpdatePostHandler)
        privateRoutes.post("fez", fezIDParam, "update", use: fezCreateOrUpdatePostHandler)
        
        privateRoutes.post("fez", fezIDParam, "join", use: fezJoinPostHandler)
        privateRoutes.post("fez", fezIDParam, "leave", use: fezLeavePostHandler)
        privateRoutes.post("fez", fezIDParam, "post", use: fezThreadPostHandler)
		privateRoutes.get("fez", "report", fezIDParam, use: fezReportPageHandler)
		privateRoutes.post("fez", "report", fezIDParam, use: fezReportPostHandler)
		
		// Mods only
		privateRoutes.post("fez", fezIDParam, "delete", use: fezDeleteHandler)
		privateRoutes.delete("fez", fezIDParam, use: fezDeleteHandler)
	}
	
// MARK: - FriendlyFez

	enum FezTab: String, Codable {
		case find, joined, owned
	}

	// GET /fez
	// Shows the root Fez page, with a list of all conversations.
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
					trunk = .init(req, title: "FriendlyFez", tab: .none)
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
	
	// Shows the Joined Fezzes page.
	func joinedFezPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/joined?excludetype=closed").throwingFlatMap { response in
			let fezzes = try response.content.decode([FezData].self)
			struct JoinedFezPageContext : Encodable {
				var trunk: TrunkContext
				var fezzes: [FezData]
				var tab: FezTab
				
				init(_ req: Request, fezzes: [FezData]) throws {
					trunk = .init(req, title: "FriendlyFez", tab: .none)
					self.fezzes = fezzes
					tab = .joined
				}
			}
			let ctx = try JoinedFezPageContext(req, fezzes: fezzes)
			return req.view.render("Fez/fezJoined", ctx)
		}
	}
	
	// Shows the Owned Fezzes page.
	func ownedFezPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/owner?excludetype=closed").throwingFlatMap { response in
			let fezzes = try response.content.decode([FezData].self)
			struct OwnedFezPageContext : Encodable {
				var trunk: TrunkContext
				var fezzes: [FezData]
				var tab: FezTab
				
				init(_ req: Request, fezzes: [FezData]) throws {
					trunk = .init(req, title: "FriendlyFez", tab: .none)
					self.fezzes = fezzes
					tab = .owned
				}
			}
			let ctx = try OwnedFezPageContext(req, fezzes: fezzes)
			return req.view.render("Fez/fezOwned", ctx)
		}
	}
	
    
    // Shows the Create New Friendly Fez page
    func fezCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		let ctx = try FezCreateUpdatePageContext(req)
		return req.view.render("Fez/fezCreate", ctx)
    }

	/// `/fez/ID/update`
	/// `/fez/ID/edit`
	/// Shows the Update Friendly Fez page.
    func fezUpdatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
    		throw "Invalid fez ID"
    	}
		return apiQuery(req, endpoint: "/fez/\(fezID)").throwingFlatMap { response in
			let fez = try response.content.decode(FezData.self)
			let ctx = try FezCreateUpdatePageContext(req, fezToUpdate: fez)
			return req.view.render("Fez/fezCreate", ctx)
		}
    }
    
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
		if let updatingFezID = req.parameters.get(fezIDParam.paramString) {
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
    
    // Shows a single Fez.
    func singleFezPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
    		throw "Invalid fez ID"
    	}
		return apiQuery(req, endpoint: "/fez/\(fezID)").throwingFlatMap { response in
			let fez = try response.content.decode(FezData.self)
			struct FezPageContext : Encodable {
				var trunk: TrunkContext
				var fez: FezData
    			var oldPosts: [LeafFezPostData]
    			var showDivider: Bool
    			var newPosts: [LeafFezPostData]
     			var post: MessagePostContext
				
				init(_ req: Request, fez: FezData) throws {
					trunk = .init(req, title: "FriendlyFez", tab: .none)
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
									oldPosts.append(LeafFezPostData(post: post, author: author))
								}
							}
							else {
								if let author = participantDictionary[post.authorID] {
									newPosts.append(LeafFezPostData(post: post, author: author))
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

	func fezThreadPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = PostContentData(text: postStruct.postText ?? "", images: [])
		return apiQuery(req, endpoint: "/fez/\(fezID)/post", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
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
	
	func fezJoinPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/join", method: .POST).flatMapThrowing { response in
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
		
	func fezLeavePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
    	return apiQuery(req, endpoint: "/fez/\(fezID)/unjoin", method: .POST).flatMapThrowing { response in
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
		
	func fezReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let ctx = try ReportPageContext(req, fezID: fezID)
    	return req.view.render("reportCreate", ctx)
    }
    
	func fezReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
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
    
	/// Handles the POST of a delete request for a fez. Moderators only..
    func fezDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let fez = req.parameters.get(fezIDParam.paramString) else {
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
