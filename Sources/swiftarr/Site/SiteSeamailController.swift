import Crypto
import FluentSQL
import Vapor

struct SiteSeamailController: SiteControllerUtils {

	struct SeamailCreateFormContent: Content {
		var subject: String
		var postText: String
		var participants: String  // Comma separated list of participant usernames
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
		privateRoutes.get("seamail", chatGroupIDParam, use: seamailViewPageHandler)
		privateRoutes.post("seamail", chatGroupIDParam, use: seamailViewPageHandler)
		privateRoutes.post("seamail", chatGroupIDParam, "post", use: seamailThreadPostHandler)
		privateRoutes.webSocket(
			"seamail",
			chatGroupIDParam,
			"socket",
			shouldUpgrade: shouldCreateMsgSocket,
			onUpgrade: createMsgSocket
		)
	}

	// MARK: - Seamail
	// GET /seamail
	//
	// Shows the root Seamail page, with a list of all conversations.
	func seamailRootPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/chatgroup/joined?type=closed&type=open")
		let chatGroupList = try response.content.decode(ChatGroupListData.self)
		// Re-sort chatgroups so ones with new msgs are first. Keep most-recent-change sort within each group.
		var newMsgChatGroups: [ChatGroupData] = []
		var noNewMsgChatGroups: [ChatGroupData] = []
		chatGroupList.chatgroups.forEach {
			if let members = $0.members, members.postCount > members.readCount {
				newMsgChatGroups.append($0)
			}
			else {
				noNewMsgChatGroups.append($0)
			}
		}
		let allChatGroups = newMsgChatGroups + noNewMsgChatGroups
		struct SeamailRootPageContext: Encodable {
			var trunk: TrunkContext
			var chatGroupList: ChatGroupListData
			var chatgroups: [ChatGroupData]
			var effectiveUser: String?
			var paginator: PaginatorContext
			var filterURL: String
			var filterActive: Bool
			var noSeamails: String

			init(_ req: Request, chatGroupList: ChatGroupListData, chatgroups: [ChatGroupData]) throws {
				effectiveUser = req.query[String.self, at: "foruser"]
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab, search: "Search Seamail")
				self.chatGroupList = chatGroupList
				self.chatgroups = chatgroups
				let limit = chatGroupList.paginator.limit
				paginator = .init(chatGroupList.paginator) { pageIndex in
					"/seamail?start=\(pageIndex * limit)&limit=\(limit)"
				}
				filterActive = req.query[String.self, at: "onlynew"]?.lowercased() == "true"
				filterURL = filterActive ? "/seamail" : "/seamail?onlynew=true"
				noSeamails =
					"You haven't received any Seamail messages yet, but you can create one by tapping \"New Seamail\""
			}
		}
		let ctx = try SeamailRootPageContext(req, chatGroupList: chatGroupList, chatgroups: allChatGroups)
		return try await req.view.render("ChatGroup/seamails", ctx)
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

		let response = try await apiQuery(req, endpoint: "/chatgroup/joined?type=closed&type=open")
		let chatGroupList = try response.content.decode(ChatGroupListData.self)
		struct SeamailRootPageContext: Encodable {
			var trunk: TrunkContext
			var chatGroupList: ChatGroupListData
			var chatgroups: [ChatGroupData]
			var effectiveUser: String?
			var paginator: PaginatorContext
			var filterURL: String
			var filterActive: Bool
			var filterEnable: Bool
			var noSeamails: String

			init(_ req: Request, searchParams: SeamailQueryOptions, chatGroupList: ChatGroupListData, chatgroups: [ChatGroupData]) throws {
				effectiveUser = req.query[String.self, at: "foruser"]
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab, search: "Search Seamail")
				self.chatGroupList = chatGroupList
				self.chatgroups = chatgroups
				let limit = chatGroupList.paginator.limit
				paginator = .init(chatGroupList.paginator) { pageIndex in
					// "/seamail/search?start=\(pageIndex * limit)&limit=\(limit)"
					return searchParams.buildQuery(baseURL: "/seamail/search", startOffset: pageIndex * limit)
						?? "/seamail/search"
				}
				// filterActive = searchParams.onlynew ?? false
				// filterURL = filterActive ? "/seamail" : "/seamail?onlynew=true"
				filterActive = false
				filterURL = ""
				filterEnable = false
				noSeamails =
					"No search results found. Try another search, or start a new Seamail by tapping \"New Seamail\"."
			}
		}
		let ctx = try SeamailRootPageContext(req, searchParams: searchParams, chatGroupList: chatGroupList, chatgroups: chatGroupList.chatgroups)
		return try await req.view.render("ChatGroup/seamails", ctx)
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

		struct SeamaiCreatePageContext: Encodable {
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
		return try await req.view.render("ChatGroup/seamailCreate", ctx)
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
		// Normally we let the API do validations, but in this case we make one call to create the ChatGroup and another
		// to post the message. Catching likely errors here reduces the chance we have to deal with partial failure.
		guard formContent.subject.count > 0 else {
			throw Abort(.badRequest, reason: "Subject cannot be empty.")
		}
		guard formContent.postText.count > 0 else {
			throw Abort(.badRequest, reason: "First message cannot be empty.")
		}
		let lines = formContent.postText.replacingOccurrences(of: "\r\n", with: "\r").components(separatedBy: .newlines)
			.count
		guard lines <= 25 else {
			throw Abort(.badRequest, reason: "Messages are limited to 25 lines of text.")
		}
		let participants = formContent.participants.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
		var allUsers = Set(participants)
		allUsers.insert(user.userID)
		guard allUsers.count >= 2 else {
			throw Abort(.badRequest, reason: "Seamail conversations require at least 2 users.")
		}

		let chatGroupType = formContent.openchat == nil ? ChatGroupType.closed : ChatGroupType.open
		let chatGroupContent = ChatGroupContentData(
			chatGroupType: chatGroupType,
			title: formContent.subject,
			info: "",
			startTime: nil,
			endTime: nil,
			location: nil,
			minCapacity: 0,
			maxCapacity: 0,
			initialUsers: participants,
			createdByModerator: formContent.postAsModerator != nil,
			createdByTwitarrTeam: formContent.postAsTwitarrTeam != nil
		)
		let createResponse = try await apiQuery(req, endpoint: "/chatgroup/create", method: .POST, encodeContent: chatGroupContent)
		let chatGroupData = try createResponse.content.decode(ChatGroupData.self)
		do {
			let postContentData = PostContentData(
				text: formContent.postText,
				images: [],
				postAsModerator: formContent.postAsModerator != nil,
				postAsTwitarrTeam: formContent.postAsTwitarrTeam != nil
			)
			let response = try await apiQuery(
				req,
				endpoint: "/chatgroup/\(chatGroupData.chatGroupID)/post",
				method: .POST,
				encodeContent: postContentData
			)
			return try await response.encodeResponse(for: req)
		}
		catch {
			// If we successfully create the chat but can't add the initial message to it, redirect to the new chat.
			let headers = HTTPHeaders(dictionaryLiteral: ("Location", "/seamail/\(chatGroupData.chatGroupID)"))
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
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)")
		let chatgroup = try response.content.decode(ChatGroupData.self)
		guard chatgroup.members != nil else {
			throw Abort(.forbidden, reason: "You are not a member of this seamail.")
		}
		struct SeamailThreadPageContext: Encodable {
			var trunk: TrunkContext
			var chatgroup: ChatGroupData
			var oldPosts: [SocketChatGroupPostData]
			var showDivider: Bool
			var newPosts: [SocketChatGroupPostData]
			var post: MessagePostContext
			var socketURL: String
			var breadcrumbURL: String
			var paginator: PaginatorContext

			init(_ req: Request, chatgroup: ChatGroupData) throws {
				let (title, tab) = titleAndTab(for: req)
				trunk = .init(req, title: title, tab: tab, search: "Search Seamail")
				self.chatgroup = chatgroup
				oldPosts = []
				newPosts = []
				showDivider = false
				post = .init(forType: .seamailPost(chatgroup))
				if req.method == .POST, let formContent = try? req.content.decode(SeamailCreateFormContent.self) {
					post.messageText = formContent.postText
					post.postErrorString = "Created the chat, but was not able to post the initial message."
				}
				socketURL = "/chatgroup/\(chatgroup.chatGroupID)/socket"
				breadcrumbURL = "/seamail"
				if let foruser = req.query[String.self, at: "foruser"],
					var comp = URLComponents(string: post.postSuccessURL)
				{
					comp.query = "foruser=\(foruser)"
					if let newstr = comp.string {
						post.postSuccessURL = newstr
					}
					socketURL.append("?foruser=\(foruser)")
					breadcrumbURL.append("?foruser=\(foruser)")
				}
				paginator = PaginatorContext(
					start: 0,
					total: 40,
					limit: 50,
					urlForPage: { pageIndex in
						"/seamail/\(chatgroup.chatGroupID)?start=\(pageIndex * 50)&limit=50"
					}
				)
				if let members = chatgroup.members, let posts = members.posts, let paginator = members.paginator {
					for index in 0..<posts.count {
						let post = posts[index]
						if index + paginator.start < members.readCount {
							oldPosts.append(SocketChatGroupPostData(post: post))
						}
						else {
							newPosts.append(SocketChatGroupPostData(post: post))
						}
					}
					self.showDivider = oldPosts.count > 0 && newPosts.count > 0
					let limit = paginator.limit
					self.paginator = PaginatorContext(paginator) { pageIndex in
						"/seamail/\(chatgroup.chatGroupID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
				}
			}
		}
		let ctx = try SeamailThreadPageContext(req, chatgroup: chatgroup)
		return try await req.view.render("ChatGroup/seamailThread", ctx)
	}

	// GET /seamail/:seamail_ID/socket
	func shouldCreateMsgSocket(_ req: Request) async throws -> HTTPHeaders? {
		guard let paramVal = req.parameters.get(chatGroupIDParam.paramString), let seamailID = UUID(uuidString: paramVal)
		else {
			throw Abort(.badRequest, reason: "Request parameter lfg_ID is missing.")
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(seamailID)")
		let seamail = try response.content.decode(ChatGroupData.self)
		// Although moderators can see into any LFG chat, they can't get make a websocket for chats they aren't in.
		guard let _ = seamail.members else {
			return nil
		}
		return HTTPHeaders()
	}

	// WS /seamail/:seamail_ID/socket
	//
	// Takes the `foruser` parameter which is forwarded to `/api/v3/chatgroup/:chatgroup_ID`
	// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	//
	// Opens a WebSocket that receives updates on the given Seamail. This websocket is intended for use by the
	// web client and updates are in the form of HTML fragments.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createMsgSocket(_ req: Request, _ ws: WebSocket) async {
		guard let user = try? req.auth.require(UserCacheData.self),
			let lfgID = req.parameters.get(chatGroupIDParam.paramString, as: UUID.self)
		else {
			try? await ws.close()
			return
		}
		let userSocket = UserSocket(userID: user.userID, socket: ws, chatGroupID: lfgID, htmlOutput: true)
		try? req.webSocketStore.storeChatGroupSocket(userSocket)

		ws.onClose.whenComplete { result in
			try? req.webSocketStore.removeChatGroupSocket(userSocket)
		}
	}

	// POST /seamail/:seamail_ID/post
	//
	// Creates a new message in a seamail thread.
	func seamailThreadPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/post", method: .POST, encodeContent: postContent)
		return .created
	}
}

// Returns the correct page title and tab name for the effective user.
// Fileprivate (instead of in an extension) because struct initializers can't access their containing object.
private func titleAndTab(for req: Request) -> (String, TrunkContext.Tab) {
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
