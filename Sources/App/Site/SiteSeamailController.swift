import Vapor
import Crypto
import FluentSQL

struct SiteSeamailController: SiteControllerUtils {

	struct SeamailCreateFormContent : Content {
		var subject: String
		var postText: String
		var participants: String			// Comma separated list of participant usernames
		var openchat: String?
		var postAsModerator: String?
		var postAsTwitarrTeam: String?
	}

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .seamail))
		globalRoutes.get("seamail", use: seamailRootPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .seamail))
		privateRoutes.get("seamail", "search", use: seamailSearchHandler)
		privateRoutes.get("seamail", "create", use: seamailCreatePageHandler)
		privateRoutes.get("seamail", "usernames", "search", ":searchString", use: seamailUsernameAutocompleteHandler)
		privateRoutes.post("seamail", "create", use: seamailCreatePostHandler)
		privateRoutes.get("seamail", fezIDParam, use: seamailViewPageHandler)
		privateRoutes.post("seamail", fezIDParam, use: seamailViewPageHandler)
		privateRoutes.post("seamail", fezIDParam, "post", use: seamailThreadPostHandler)
		privateRoutes.webSocket("seamail", fezIDParam, "socket", shouldUpgrade: shouldCreateMsgSocket, onUpgrade: createMsgSocket) 
	}
	
// MARK: - Seamail
	// GET /seamail
	//
	// Shows the root Seamail page, with a list of all conversations.
	func seamailRootPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/joined?type=closed&type=open")
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
			var filterURL: String
			var filterActive: Bool
			var noSeamails: String
			
			init(_ req: Request, fezList: FezListData, fezzes: [FezData]) throws {
				effectiveUser = req.query[String.self, at: "foruser"]
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab, search: "Search Seamail")
				self.fezList = fezList
				self.fezzes = fezzes
				let limit = fezList.paginator.limit
				paginator = .init(fezList.paginator) { pageIndex in
					"/seamail?start=\(pageIndex * limit)&limit=\(limit)"
				}
				filterActive = req.query[String.self, at: "onlynew"]?.lowercased() == "true"
				filterURL = filterActive ? "/seamail" : "/seamail?onlynew=true"
				noSeamails = "You haven't received any Seamail messages yet, but you can create one by tapping \"New Seamail\""
			}
		}
		let ctx = try SeamailRootPageContext(req, fezList: fezList, fezzes: allFezzes)
		return try await req.view.render("Fez/seamails", ctx)
	}

	struct SeamailQueryOptions: Content {
		var search: String?
		var start: Int?
		var limit: Int?
		var onlynew: Bool? 

		func buildQuery(baseURL: String, startOffset: Int?) -> String? {
			guard var components = URLComponents(string: baseURL) else {
				return nil
			}
			// We don't expose the type=open&type=closed paramters here because they could
			// get overridden elsewhere.
			var elements = [URLQueryItem]()
			if let search = search { elements.append(URLQueryItem(name: "search", value: search)) }
			let newOffset = max(startOffset ?? start ?? 0, 0)
			if newOffset != 0 { elements.append(URLQueryItem(name: "start", value: String(newOffset))) }
			if let limit = limit { elements.append(URLQueryItem(name: "limit", value: String(limit))) }
			if let onlynew = onlynew { elements.append(URLQueryItem(name: "onlynew", value: String(onlynew))) }

			components.queryItems = elements
			return components.string
		}
	}

	// GET /seamail/search
	//
	// Searches seamail
	func seamailSearchHandler(_ req: Request) async throws -> View {
		let searchParams = try req.query.decode(SeamailQueryOptions.self)

		let response = try await apiQuery(req, endpoint: "/fez/joined?type=closed&type=open")
		let fezList = try response.content.decode(FezListData.self)
		struct SeamailRootPageContext : Encodable {
			var trunk: TrunkContext
			var fezList: FezListData
			var fezzes: [FezData]
			var effectiveUser: String?
			var paginator: PaginatorContext
			var filterURL: String
			var filterActive: Bool
			var filterEnable: Bool
			var noSeamails: String
			
			init(_ req: Request, searchParams: SeamailQueryOptions, fezList: FezListData, fezzes: [FezData]) throws {
				effectiveUser = req.query[String.self, at: "foruser"]
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab, search: "Search Seamail")
				self.fezList = fezList
				self.fezzes = fezzes
				let limit = fezList.paginator.limit
				paginator = .init(fezList.paginator) { pageIndex in
					// "/seamail/search?start=\(pageIndex * limit)&limit=\(limit)"
					return searchParams.buildQuery(baseURL: "/seamail/search", startOffset: pageIndex * limit) ?? "/seamail/search"
				}
				// filterActive = searchParams.onlynew ?? false
				// filterURL = filterActive ? "/seamail" : "/seamail?onlynew=true"
				filterActive = false
				filterURL = ""
				filterEnable = false
				noSeamails = "No search results found. Try another search, or start a new Seamail by tapping \"New Seamail\"."
			}
		}
		let ctx = try SeamailRootPageContext(req, searchParams: searchParams, fezList: fezList, fezzes: fezList.fezzes)
		return try await req.view.render("Fez/seamails", ctx)
	}
	
	// GET /seamail/create
	//
	// Query Parameters:
	// * `?withuser=UUID` - prefills the participant list with the given user. Currently can only be applied once.
	//
	// Shows the Create New Seamail page. This page lets you add users to the chat, and give the chat a subject and initial message.
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
				trunk = .init(req, title: "New Seamail", tab: .seamail, search: "Search Seamail")
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
		let formContent = try req.content.decode(SeamailCreateFormContent.self)
		// Normally we let the API do validations, but in this case we make one call to create the Fez and another
		// to post the message. Catching likely errors here reduces the chance we have to deal with partial failure.
		guard formContent.subject.count > 0 else {
			throw Abort(.badRequest, reason: "Subject cannot be empty.")
		}
		guard formContent.postText.count > 0 else {
			throw Abort(.badRequest, reason: "First message cannot be empty.")
		}
		let lines = formContent.postText.replacingOccurrences(of: "\r\n", with: "\r").components(separatedBy: .newlines).count
		guard lines <= 25 else {
			throw Abort(.badRequest, reason: "Messages are limited to 25 lines of text.")
		}
		let participants = formContent.participants.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
		var allUsers = Set(participants)
		allUsers.insert(user.userID)
		guard allUsers.count >= 2 else {
			throw Abort(.badRequest, reason: "Seamail conversations require at least 2 users.")
		}
		
		let fezType = formContent.openchat == nil ? FezType.closed : FezType.open
		let fezContent = FezContentData(fezType: fezType, title: formContent.subject, info: "", startTime: nil, endTime: nil,
				location: nil, minCapacity: 0, maxCapacity: 0, initialUsers: participants, createdByModerator: formContent.postAsModerator != nil, 
				createdByTwitarrTeam: formContent.postAsTwitarrTeam != nil)
		let createResponse = try await apiQuery(req, endpoint: "/fez/create", method: .POST, encodeContent: fezContent)
		let fezData = try createResponse.content.decode(FezData.self)
		do {
			let postContentData = PostContentData(text: formContent.postText, images: [], postAsModerator: formContent.postAsModerator != nil, 
					postAsTwitarrTeam: formContent.postAsTwitarrTeam != nil)
			let response = try await apiQuery(req, endpoint: "/fez/\(fezData.fezID)/post", method: .POST, encodeContent: postContentData)
			return try await response.encodeResponse(for: req)
		}
		catch {
			// If we successfully create the chat but can't add the initial message to it, redirect to the new chat.
			let headers = HTTPHeaders(dictionaryLiteral: ("Location", "/seamail/\(fezData.fezID)"))
			let response = Response(status: .badRequest, headers: headers)
			return response
		}
	}
	
	// GET /seamail/:seamail_ID
	// POST /seamail/:seamail_ID 		-- only used for cases where we create a chat but then the initial post fails
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
		guard fez.members != nil else {
			throw Abort(.forbidden, reason: "You are not a member of this seamail.")
		}
		struct SeamailThreadPageContext : Encodable {
			var trunk: TrunkContext
			var fez: FezData
			var oldPosts: [SocketFezPostData]
			var showDivider: Bool
			var newPosts: [SocketFezPostData]
			var post: MessagePostContext
			var socketURL: String
			var breadcrumbURL: String
			var paginator: PaginatorContext
						
			init(_ req: Request, fez: FezData) throws {
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab, search: "Search Seamail")
				self.fez = fez
				oldPosts = []
				newPosts = []
				showDivider = false
				post = .init(forType: .seamailPost(fez))
				if req.method == .POST, let formContent = try? req.content.decode(SeamailCreateFormContent.self) {
					post.messageText = formContent.postText
					post.postErrorString = "Created the chat, but was not able to post the initial message."
				}
				socketURL = "/fez/\(fez.fezID)/socket"
				breadcrumbURL = "/seamail"
				if let foruser = req.query[String.self, at: "foruser"], var comp = URLComponents(string: post.postSuccessURL) {
					comp.query = "foruser=\(foruser)"
					if let newstr = comp.string {
						post.postSuccessURL = newstr
					}
					socketURL.append("?foruser=\(foruser)")
					breadcrumbURL.append("?foruser=\(foruser)")
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
	
	// GET /seamail/:seamail_ID/socket
	func shouldCreateMsgSocket(_ req: Request) async throws -> HTTPHeaders? {
  		guard let paramVal = req.parameters.get(fezIDParam.paramString), let seamailID = UUID(uuidString: paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter lfg_ID is missing.")
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(seamailID)")
		let seamail = try response.content.decode(FezData.self)
		// Although moderators can see into any LFG chat, they can't get make a websocket for chats they aren't in.
		guard let _ = seamail.members else {
			return nil
		}
		return HTTPHeaders()
	}
	
	// WS /seamail/:seamail_ID/socket
	//
	// Takes the `foruser` parameter which is forwarded to `/api/v3/fez/:fez_ID`
	// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	//
	// Opens a WebSocket that receives updates on the given Seamail. This websocket is intended for use by the
	// web client and updates are in the form of HTML fragments.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createMsgSocket(_ req: Request, _ ws: WebSocket) async {
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

	// POST /seamail/:seamail_ID/post
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
