import Vapor
import Crypto
import FluentSQL

struct SiteSeamailController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .seamail))
        globalRoutes.get("seamail", use: seamailRootPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .seamail))
        privateRoutes.get("seamail", "create", use: seamailCreatePageHandler)
        privateRoutes.get("seamail", "usernames", "search", ":searchString", use: seamailUsernameAutocompleteHandler)
        privateRoutes.post("seamail", "create", use: seamailCreatePostHandler)
        privateRoutes.get("seamail", fezIDParam, use: seamailViewPageHandler)
        privateRoutes.post("seamail", fezIDParam, "post", use: seamailThreadPostHandler)
	}
	
// MARK: - Seamail
	// Shows the root Seamail page, with a list of all conversations.
    func seamailRootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/joined?type=closed").throwingFlatMap { response in
 			let fezzes = try response.content.decode([FezData].self)
     		struct SeamailRootPageContext : Encodable {
				var trunk: TrunkContext
    			var fezzes: [FezData]
    			
    			init(_ req: Request, fezzes: [FezData]) throws {
    				trunk = .init(req, title: "Seamail", tab: .seamail)
    				self.fezzes = fezzes
    			}
    		}
    		let ctx = try SeamailRootPageContext(req, fezzes: fezzes)
			return req.view.render("Fez/seamails", ctx)
    	}
    }
    
    // Shows the Create New Seamail page
    func seamailCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct SeamaiCreatePageContext : Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "New Seamail", tab: .seamail)
				post = .init(forType: .seamail)
			}
		}
		let ctx = try SeamaiCreatePageContext(req)
		return req.view.render("Fez/seamailCreate", ctx)
    }
    
    // Called by JS when searching for usernames to add to a seamail.
    func seamailUsernameAutocompleteHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let searchString = req.parameters.get("searchString")?.percentEncodeFilePathEntry() else {
    		throw "Missing search string"
    	}
		return apiQuery(req, endpoint: "/users/match/allnames/\(searchString)").flatMap { response in
			return response.encodeResponse(for: req)
		}
    }
    
    // POSTs a seamail creation request.
    func seamailCreatePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	let user = try req.auth.require(UserCacheData.self)
    	struct SeamailCreateFormContent : Content {
    		var subject: String
    		var postText: String
    		var participants: String			// ??
    	}
		let formContent = try req.content.decode(SeamailCreateFormContent.self)
		guard formContent.subject.count > 0 else {
			throw Abort(.badRequest, reason: "Subject cannot be empty.")
		}
		guard formContent.postText.count > 0 else {
			throw Abort(.badRequest, reason: "First message cannot be empty.")
		}
		let participants = formContent.participants.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
		var allUsers = Set(participants)
		allUsers.insert(user.userID)
		guard allUsers.count >= 2 else {
			throw Abort(.badRequest, reason: "Seamail conversations require at least 2 users.")
		}
		let fezContent = FezContentData(fezType: .closed, title: formContent.subject, info: "", startTime: nil, endTime: nil,
				location: nil, minCapacity: 0, maxCapacity: 0, initialUsers: participants)
    	return apiQuery(req, endpoint: "/fez/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(fezContent)
		}).throwingFlatMap { response in
			guard response.status.code < 300 else {
				return response.encodeResponse(for: req)
			}
			let fezData = try response.content.decode(FezData.self)
			return apiQuery(req, endpoint: "/fez/\(fezData.fezID)/post", method: .POST, beforeSend: { req throws in
				let postContentData = PostContentData(text: formContent.postText, images: [])
				try req.content.encode(postContentData)
			}).throwingFlatMap { response in
				guard response.status.code < 300 else {
					var errorResponse = try response.content.decode(ErrorResponse.self)
					errorResponse.reason = "The conversation was created, but the first post couldn't be added to it because: " + 
							errorResponse.reason
					throw errorResponse
				}
				return response.encodeResponse(for: req)
			}
    	}
    }
    
    // Shows a seamail thread. Participants up top, then a list of messages, then a form for composing.
	func seamailViewPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw Abort(.badRequest, reason: "Missing fez_id")
    	}
		return apiQuery(req, endpoint: "/fez/\(fezID)").throwingFlatMap { response in
 			let fez = try response.content.decode(FezData.self)
     		struct SeamailThreadPageContext : Encodable {
				var trunk: TrunkContext
    			var fez: FezData
    			var oldPosts: [LeafFezPostData]
    			var showDivider: Bool
    			var newPosts: [LeafFezPostData]
     			var post: MessagePostContext
   			    			
    			init(_ req: Request, fez: FezData) throws {
    				trunk = .init(req, title: "Seamail", tab: .seamail)
    				self.fez = fez
    				oldPosts = []
    				newPosts = []
    				showDivider = false
    				post = .init(forType: .seamailPost(fez))
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
    		let ctx = try SeamailThreadPageContext(req, fez: fez)
			return req.view.render("Fez/seamailThread", ctx)
    	}
	}
	
	func seamailThreadPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw Abort(.badRequest, reason: "Missing fez_id")
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = PostContentData(text: postStruct.postText ?? "", images: [])
    	return apiQuery(req, endpoint: "/fez/\(fezID)/post", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
// 			let fez = try response.content.decode(FezData.self)
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
}
