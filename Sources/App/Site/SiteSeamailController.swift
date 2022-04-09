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
		privateRoutes.webSocket("seamail", fezIDParam, "socket", shouldUpgrade: shouldCreateFezSocket, onUpgrade: createFezSocket) 
	}
	
// MARK: - Seamail
	// GET /seamail
	//
	// Shows the root Seamail page, with a list of all conversations.
	func seamailRootPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/joined?type=closed")
		let fezList = try response.content.decode(FezListData.self)
		// Re-sort fezzes so ones with new msgs are first. Keep most-recent-change sort within each group.
		var newMsgFezzes: [FezData] = []
		var noNewMsgFezzes: [FezData] = []
		fezList.fezzes.forEach {
			if let members = $0.members, members.postCount > members.readCount {
				newMsgFezzes.append($0)
			}
			else {
				noNewMsgFezzes.append($0)
			}
		}
		let allFezzes = newMsgFezzes + noNewMsgFezzes
		struct SeamailRootPageContext : Encodable {
			var trunk: TrunkContext
			var fezList: FezListData
			var fezzes: [FezData]
			var effectiveUser: String?
			var paginator: PaginatorContext
			
			init(_ req: Request, fezList: FezListData, fezzes: [FezData]) throws {
				effectiveUser = req.query[String.self, at: "foruser"]
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab)
				self.fezList = fezList
				self.fezzes = fezzes
				let limit = fezList.paginator.limit
				paginator = .init(fezList.paginator) { pageIndex in
					"/seamail?start=\(pageIndex * limit)&limit=\(limit)"
				}

			}
		}
		let ctx = try SeamailRootPageContext(req, fezList: fezList, fezzes: allFezzes)
		return try await req.view.render("Fez/seamails", ctx)
	}
	
	// GET /seamail/create
	//
	// Query Parameters:
	// * `?withuser=UUID` - auto-adds the given user to the conversation.
	//
	// Shows the Create New Seamail page
	func seamailCreatePageHandler(_ req: Request) async throws -> View {
		var withUser: UserHeader?
		if let initialUser = req.query[UUID.self, at: "withuser"] {
			let response = try await apiQuery(req, endpoint: "/users/\(initialUser)")
			withUser = try response.content.decode(UserHeader.self)
		}
		
		struct SeamaiCreatePageContext : Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext
			var withUser: UserHeader?
			
			init(_ req: Request, withUser: UserHeader?) throws {
				trunk = .init(req, title: "New Seamail", tab: .seamail)
				self.withUser = withUser
				post = .init(forType: .seamail)
			}
		}
		let ctx = try SeamaiCreatePageContext(req, withUser: withUser)
		return try await req.view.render("Fez/seamailCreate", ctx)
	}
	
	// GET /seamail/usernames/search/STRING
	//
	// Called by JS when searching for usernames to add to a seamail.
	func seamailUsernameAutocompleteHandler(_ req: Request) async throws -> Response {
		guard let searchString = req.parameters.get("searchString")?.percentEncodeFilePathEntry() else {
			throw "Missing search string"
		}
		let response = try await apiQuery(req, endpoint: "/users/match/allnames/\(searchString)")
		return try await response.encodeResponse(for: req)
	}
	
	// POST /seamail/create
	//
	// POSTs a seamail creation request.
	func seamailCreatePostHandler(_ req: Request) async throws -> Response {
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
		let createResponse = try await apiQuery(req, endpoint: "/fez/create", method: .POST, encodeContent: fezContent)
		let fezData = try createResponse.content.decode(FezData.self)
		let postContentData = PostContentData(text: formContent.postText, images: [])
		let response = try await apiQuery(req, endpoint: "/fez/\(fezData.fezID)/post", method: .POST, encodeContent: postContentData)
		return try await response.encodeResponse(for: req)
	}
	
	// GET /seamail/:fez_ID
	//
	// Paginated.
	// 
	// Shows a seamail thread. Participants up top, then a list of messages, then a form for composing.
	func seamailViewPageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(fezID)")
		let fez = try response.content.decode(FezData.self)
		struct SeamailThreadPageContext : Encodable {
			var trunk: TrunkContext
			var fez: FezData
			var oldPosts: [SocketFezPostData]
			var showDivider: Bool
			var newPosts: [SocketFezPostData]
			var post: MessagePostContext
			var paginator: PaginatorContext
						
			init(_ req: Request, fez: FezData) throws {
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab)
				self.fez = fez
				oldPosts = []
				newPosts = []
				showDivider = false
				post = .init(forType: .seamailPost(fez))
				if let foruser = req.query[String.self, at: "foruser"], var comp = URLComponents(string: post.postSuccessURL) {
					comp.query = "foruser=\(foruser)"
					if let newstr = comp.string {
						post.postSuccessURL = newstr
					}
				}
				paginator = PaginatorContext(start: 0, total: 40, limit: 50, urlForPage: { pageIndex in
					"/seamail/\(fez.fezID)?start=\(pageIndex * 50)&limit=50"
				})
				if let members = fez.members, let posts = members.posts, let paginator = members.paginator {
					for index in 0..<posts.count {
						let post = posts[index]
						if index + paginator.start < members.readCount {
							oldPosts.append(SocketFezPostData(post: post))
						}
						else {
							newPosts.append(SocketFezPostData(post: post))
						}
					} 
					self.showDivider = oldPosts.count > 0 && newPosts.count > 0
					let limit = paginator.limit
					self.paginator = PaginatorContext(paginator) { pageIndex in
						"/seamail/\(fez.fezID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
				}
			}
		}
		let ctx = try SeamailThreadPageContext(req, fez: fez)
		return try await req.view.render("Fez/seamailThread", ctx)
	}
	
	// GET /seamail/:lfg_ID/socket
	func shouldCreateFezSocket(_ req: Request) async throws -> HTTPHeaders? {
		let user = try req.auth.require(UserCacheData.self)
  		guard let paramVal = req.parameters.get(fezIDParam.paramString), let lfgID = UUID(uuidString: paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter lfg_ID is missing.")
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(lfgID)")
		let lfg = try response.content.decode(FezData.self)
		// Although moderators can see into any LFG chat, they can't get make a websocket for chats they aren't in.
		guard let members = lfg.members, members.participants.contains(where: { $0.userID == user.userID }) || 
				members.waitingList.contains(where: { $0.userID == user.userID }) else {
			return nil
		}
		return HTTPHeaders()
	}
	
	// WS /seamail/:lfg_ID/socket
	//
	// Opens a WebSocket that receives updates on the given Seamail. This websocket is intended for use by the
	// web client and updates are in the form of HTML fragments.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createFezSocket(_ req: Request, _ ws: WebSocket) async {
		guard let user = try? req.auth.require(UserCacheData.self), let lfgID = req.parameters.get(fezIDParam.paramString, as: UUID.self) else {
			try? await ws.close()
			return 
		}
		let userSocket = UserSocket(userID: user.userID, socket: ws, fezID: lfgID, htmlOutput: true)
		try? req.webSocketStore.storeFezSocket(userSocket)

		ws.onClose.whenComplete { result in
			try? req.webSocketStore.removeFezSocket(userSocket)
		}
	}

	// POST /seamail/:fez_ID/post
	//
	// Creates a new message in a seamail thread.
	func seamailThreadPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		try await apiQuery(req, endpoint: "/fez/\(fezID)/post", method: .POST, encodeContent: postContent)
		return .created
	}
}

	
// Returns the correct page title and tab name for the effective user.
// Fileprivate (instead of in an extension) because struct initializers can't access their containing object.
fileprivate func titleAndTab(for req: Request) -> (String, TrunkContext.Tab) {
	let effectiveUser = req.query[String.self, at: "foruser"]
	var title: String
	var tab: TrunkContext.Tab
	switch effectiveUser?.lowercased() {
		case "twitarrteam": 
			title = "TwitarrTeam Seamail"
			tab = .admin
		case "moderator": 
			title = "Moderator Seamail"
			tab = .moderator
		default: 
			title = "Seamail"
			tab = .seamail
	}
	return (title, tab)
}
