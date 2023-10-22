import Crypto
import FluentSQL
import Vapor

// Form data from the Create/Update ChatGroup form
struct CreateChatGroupPostFormContent: Codable {
	var subject: String
	var location: String
	var eventtype: String
	var starttime: String
	var duration: Int
	var minimum: Int
	var maximum: Int
	var postText: String
}

struct ChatGroupCreateUpdatePageContext: Encodable {
	var trunk: TrunkContext
	var chatgroup: ChatGroupData?
	var pageTitle: String
	var chatGroupTitle: String = ""
	var chatGroupLocation: String = ""
	var chatGroupType: String = ""
	var startTime: Date?
	var minutes: Int = 0
	var minPeople: Int = 0
	var maxPeople: Int = 0
	var info: String = ""
	var formAction: String
	var submitButtonTitle: String = "Create"

	init(_ req: Request, chatGroupToUpdate: ChatGroupData? = nil) throws {
		if let chatgroup = chatGroupToUpdate {
			trunk = .init(req, title: "Update Looking For Group", tab: .lfg)
			self.chatgroup = chatGroupToUpdate
			pageTitle = "Update Looking For Group"
			chatGroupTitle = chatgroup.title
			chatGroupLocation = chatgroup.location ?? ""
			chatGroupType = chatgroup.chatGroupType.rawValue
			startTime = chatgroup.startTime
			if let start = chatgroup.startTime, let end = chatgroup.endTime {
				minutes = Int(end.timeIntervalSince(start) / 60 + 0.01)  // should be 30, 60, 90, etc.
			}
			minPeople = chatgroup.minParticipants
			maxPeople = chatgroup.maxParticipants
			info = chatgroup.info
			formAction = "/chatgroup/\(chatgroup.chatGroupID)/update"
			submitButtonTitle = "Update"
		}
		else {
			trunk = .init(req, title: "New Looking For Group", tab: .lfg)
			pageTitle = "Create a New LFG"
			formAction = "/chatgroup/create"
			minPeople = 2
			maxPeople = 2
		}
	}

	// Builds a Create ChatGroup page for a chatgroup, prefilled to play the indicated boardgame.
	// If `game` is an expansion set, you can optionally pass the baseGame in as well.
	init(_ req: Request, forGame game: BoardgameData, baseGame: BoardgameData? = nil) {
		trunk = .init(req, title: "New LFG", tab: .lfg)
		pageTitle = "Create LFG to play a Boardgame"
		chatGroupTitle = "Play \(game.gameName)"
		chatGroupLocation = "Dining Room, Deck 3 Aft"
		chatGroupType = "gaming"
		minutes = game.avgPlayingTime ?? game.minPlayingTime ?? game.maxPlayingTime ?? 0
		minPeople = game.minPlayers ?? 2
		maxPeople = game.maxPlayers ?? 2
		let copyText = game.numCopies == 1 ? "1 copy" : "\(game.numCopies) copies"
		info =
			"Play a board game! We'll be playing \"\(game.gameName)\".\n\nRemember, LFG is not a game reservation service. The game library has \(copyText) of this game."
		if let baseGame = baseGame {
			let baseGameCopyText = baseGame.numCopies == 1 ? "1 copy" : "\(baseGame.numCopies) copies"
			info.append(
				"\n\n\(game.gameName) is an expansion pack for \(baseGame.gameName). You'll need to check this out of the library too. The game library has \(baseGameCopyText) of the base game."
			)
		}
		formAction = "/chatgroup/create"
		submitButtonTitle = "Create"
	}
}

struct SitechatgroupController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		let globalRoutes = getGlobalRoutes(app).grouped("chatgroup")
			.grouped(DisabledSiteSectionMiddleware(feature: .chatgroup))
		globalRoutes.get("", use: chatGroupRootPageHandler)
		globalRoutes.get("joined", use: joinedChatGroupPageHandler)
		globalRoutes.get("owned", use: ownedChatGroupPageHandler)
		globalRoutes.get(chatGroupIDParam, use: singleChatGroupPageHandler)
		globalRoutes.get("faq", use: chatGroupFAQHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("chatgroup")
			.grouped(DisabledSiteSectionMiddleware(feature: .chatgroup))
		privateRoutes.get("create", use: chatGroupCreatePageHandler)
		privateRoutes.get(chatGroupIDParam, "update", use: chatGroupUpdatePageHandler)
		privateRoutes.get(chatGroupIDParam, "edit", use: chatGroupUpdatePageHandler)
		privateRoutes.post("create", use: chatGroupCreateOrUpdatePostHandler)
		privateRoutes.post(chatGroupIDParam, "update", use: chatGroupCreateOrUpdatePostHandler)

		privateRoutes.post(chatGroupIDParam, "join", use: chatGroupJoinPostHandler)
		privateRoutes.post(chatGroupIDParam, "leave", use: chatGroupLeavePostHandler)
		privateRoutes.post(chatGroupIDParam, "post", use: chatGroupThreadPostHandler)
		privateRoutes.post("post", postIDParam, "delete", use: chatGroupPostDeleteHandler)
		privateRoutes.delete("post", postIDParam, use: chatGroupPostDeleteHandler)
		privateRoutes.post(chatGroupIDParam, "cancel", use: chatGroupCancelPostHandler)
		privateRoutes.get(chatGroupIDParam, "members", use: chatGroupMembersPageHandler)
		privateRoutes.post(chatGroupIDParam, "members", "add", userIDParam, use: chatGroupAddUserPostHandler)
		privateRoutes.post(chatGroupIDParam, "members", "remove", userIDParam, use: chatGroupRemoveUserPostHandler)

		privateRoutes.get("report", chatGroupIDParam, use: chatGroupReportPageHandler)
		privateRoutes.post("report", chatGroupIDParam, use: chatGroupReportPostHandler)
		privateRoutes.get("post", "report", postIDParam, use: chatGroupPostReportPageHandler)
		privateRoutes.post("post", "report", postIDParam, use: chatGroupPostReportPostHandler)

		privateRoutes.webSocket(chatGroupIDParam, "socket", shouldUpgrade: shouldCreateChatGroupSocket, onUpgrade: createGroupChatSocket)

		// Mods only
		privateRoutes.post(chatGroupIDParam, "delete", use: chatGroupDeleteHandler)
		privateRoutes.delete(chatGroupIDParam, use: chatGroupDeleteHandler)
	}

	// MARK: - ChatGroup

	enum ChatGroupTab: String, Codable {
		case faq, find, joined, owned
	}

	// GET /chatgroup
	// Shows the root ChatGroup page, with a list of all chatgroups.
	func chatGroupRootPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/chatgroup/open")
		let chatGroupList = try response.content.decode(ChatGroupListData.self)
		struct ChatGroupRootPageContext: Encodable {
			var trunk: TrunkContext
			var chatGroupList: ChatGroupListData
			var paginator: PaginatorContext
			var tab: ChatGroupTab
			var typeSelection: String?
			var daySelection: Int?
			var hidePastSelection: Bool?

			init(_ req: Request, chatGroupList: ChatGroupListData) throws {
				trunk = .init(req, title: "Looking For Group", tab: .lfg)
				self.chatGroupList = chatGroupList
				tab = .find
				typeSelection = req.query[String.self, at: "type"] ?? "all"
				daySelection = req.query[Int.self, at: "cruiseday"]
				let hidePastQuery = req.query[String.self, at: "hidePast"]
				hidePastSelection = hidePastQuery == nil ? nil : hidePastQuery?.lowercased() == "true"
				let limit = chatGroupList.paginator.limit
				paginator = .init(chatGroupList.paginator) { pageIndex in
					"/chatgroup?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try ChatGroupRootPageContext(req, chatGroupList: chatGroupList)
		return try await req.view.render("ChatGroup/chatGroupRoot", ctx)
	}

	// GET /chatgroup/faq
	//
	// Shows a FAQ page for ChatGroups.
	func chatGroupFAQHandler(_ req: Request) async throws -> View {
		struct ChatGroupFAQPageContext: Encodable {
			var trunk: TrunkContext
			var tab: ChatGroupTab

			init(_ req: Request) throws {
				trunk = .init(req, title: "Looking For Group", tab: .lfg)
				tab = .faq
			}
		}
		let ctx = try ChatGroupFAQPageContext(req)
		return try await req.view.render("ChatGroup/chatGroupFAQ", ctx)
	}

	// GET /chatgroup/joined
	//
	// Shows the Joined ChatGroups page.
	func joinedChatGroupPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/chatgroup/joined?excludetype=closed&excludetype=open")
		let chatGroupList = try response.content.decode(ChatGroupListData.self)
		struct JoinedChatGroupPageContext: Encodable {
			var trunk: TrunkContext
			var chatGroupList: ChatGroupListData
			var paginator: PaginatorContext
			var tab: ChatGroupTab
			var typeSelection: String?
			var daySelection: Int?
			var hidePastSelection: Bool?

			init(_ req: Request, chatGroupList: ChatGroupListData) throws {
				trunk = .init(req, title: "LFG Joined Groups", tab: .lfg)
				self.chatGroupList = chatGroupList
				tab = .joined
				typeSelection = req.query[String.self, at: "type"] ?? "all"
				daySelection = req.query[Int.self, at: "cruiseday"]
				let hidePastQuery = req.query[String.self, at: "hidePast"]
				hidePastSelection = hidePastQuery == nil ? nil : hidePastQuery?.lowercased() == "true"
				let limit = chatGroupList.paginator.limit
				paginator = .init(chatGroupList.paginator) { pageIndex in
					"/chatgroup/joined?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try JoinedChatGroupPageContext(req, chatGroupList: chatGroupList)
		return try await req.view.render("ChatGroup/chatGroupJoined", ctx)
	}

	// GET /chatgroup/owned
	//
	// Shows the Owned ChatGroups page. These are the ChatGroups a user has created.
	func ownedChatGroupPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/chatgroup/owner?excludetype=closed&excludetype=open")
		let chatGroupList = try response.content.decode(ChatGroupListData.self)
		struct OwnedChatGroupPageContext: Encodable {
			var trunk: TrunkContext
			var chatGroupList: ChatGroupListData
			var paginator: PaginatorContext
			var tab: ChatGroupTab
			var typeSelection: String?
			var daySelection: Int?
			var hidePastSelection: Bool?

			init(_ req: Request, chatGroupList: ChatGroupListData) throws {
				trunk = .init(req, title: "LFGs Created By You", tab: .lfg)
				self.chatGroupList = chatGroupList
				tab = .owned
				typeSelection = req.query[String.self, at: "type"] ?? "all"
				daySelection = req.query[Int.self, at: "cruiseday"]
				let hidePastQuery = req.query[String.self, at: "hidePast"]
				hidePastSelection = hidePastQuery == nil ? nil : hidePastQuery?.lowercased() == "true"
				let limit = chatGroupList.paginator.limit
				paginator = .init(chatGroupList.paginator) { pageIndex in
					"/chatgroup/joined?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try OwnedChatGroupPageContext(req, chatGroupList: chatGroupList)
		return try await req.view.render("ChatGroup/chatGroupOwned", ctx)
	}

	// GET /chatgroup/create
	//
	// Shows the Create New ChatGroup page
	func chatGroupCreatePageHandler(_ req: Request) async throws -> View {
		let ctx = try ChatGroupCreateUpdatePageContext(req)
		return try await req.view.render("ChatGroup/chatGroupCreate", ctx)
	}

	// GET `/chatgroup/ID/update`
	// GET `/chatgroup/ID/edit`
	//
	// Shows the Update ChatGroup page.
	func chatGroupUpdatePageHandler(_ req: Request) async throws -> View {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid chatgroup ID"
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)")
		let chatgroup = try response.content.decode(ChatGroupData.self)
		let ctx = try ChatGroupCreateUpdatePageContext(req, chatGroupToUpdate: chatgroup)
		return try await req.view.render("ChatGroup/chatGroupCreate", ctx)
	}

	// POST /chatgroup/create
	// POST /chatgroup/ID/update
	// Handles the POST from either the Create Or Update ChatGroup page
	func chatGroupCreateOrUpdatePostHandler(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(CreateChatGroupPostFormContent.self)
		var chatGroupType: ChatGroupType
		switch postStruct.eventtype {
		case "activity": chatGroupType = .activity
		case "dining": chatGroupType = .dining
		case "gaming": chatGroupType = .gaming
		case "meetup": chatGroupType = .meetup
		case "music": chatGroupType = .music
		case "ashore": chatGroupType = .shore
		default: chatGroupType = .other
		}
		guard let startTime = dateFromW3DatetimeString(postStruct.starttime) else {
			throw Abort(.badRequest, reason: "Couldn't parse start time")
		}
		let endTime = startTime.addingTimeInterval(TimeInterval(postStruct.duration) * 60.0)
		let chatGroupContentData = ChatGroupContentData(
			chatGroupType: chatGroupType,
			title: postStruct.subject,
			info: postStruct.postText,
			startTime: startTime,
			endTime: endTime,
			location: postStruct.location,
			minCapacity: postStruct.minimum,
			maxCapacity: postStruct.maximum,
			initialUsers: []
		)
		var path = "/chatgroup/create"
		if let updatingChatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() {
			path = "/chatgroup/\(updatingChatGroupID)/update"
		}
		try await apiQuery(req, endpoint: path, method: .POST, encodeContent: chatGroupContentData)
		return .created
	}

	// GET /chatgroup/ID
	//
	// Paginated.
	//
	// Shows a single ChatGroup with all its posts.
	func singleChatGroupPageHandler(_ req: Request) async throws -> View {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid chatgroup ID"
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)")
		let chatgroup = try response.content.decode(ChatGroupData.self)
		struct ChatGroupPageContext: Encodable {
			var trunk: TrunkContext
			var chatgroup: ChatGroupData
			var userID: UUID
			var userIsMember: Bool  // TRUE if user is member
			var showModButton: Bool
			var oldPosts: [SocketChatGroupPostData]  // Posts user has read already
			var showDivider: Bool  // TRUE if there a both old and new posts
			var newPosts: [SocketChatGroupPostData]  // Posts user hasn't read.
			var post: MessagePostContext  // New post area
			var paginator: PaginatorContext  // For > 50 posts in thread.

			init(_ req: Request, chatgroup: ChatGroupData) throws {
				let cacheUser = try req.auth.require(UserCacheData.self)
				trunk = .init(req, title: "LFG", tab: .lfg)
				self.chatgroup = chatgroup
				self.userID = cacheUser.userID
				userIsMember = false
				showModButton = trunk.userIsMod && ![.closed, .open].contains(chatgroup.chatGroupType)
				oldPosts = []
				newPosts = []
				showDivider = false
				post = .init(forType: .chatGroupPost(chatgroup))
				paginator = PaginatorContext(
					start: 0,
					total: 40,
					limit: 50,
					urlForPage: { pageIndex in
						"/chatgroup/\(chatgroup.chatGroupID)?start=\(pageIndex * 50)&limit=50"
					}
				)
				if let members = chatgroup.members, let posts = members.posts, let paginator = members.paginator {
					self.userIsMember =
						members.participants.contains(where: { $0.userID == cacheUser.userID })
						|| members.waitingList.contains(where: { $0.userID == cacheUser.userID })
					for index in 0..<posts.count {
						let post = posts[index]
						if index < members.readCount {
							oldPosts.append(SocketChatGroupPostData(post: post))
						}
						else {
							newPosts.append(SocketChatGroupPostData(post: post))
						}
					}
					self.showDivider = oldPosts.count > 0 && newPosts.count > 0
					let limit = paginator.limit
					self.paginator = PaginatorContext(paginator) { pageIndex in
						"/chatgroup/\(chatgroup.chatGroupID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
				}
			}
		}
		let ctx = try ChatGroupPageContext(req, chatgroup: chatgroup)
		return try await req.view.render("ChatGroup/singleChatGroup", ctx)
	}

	// WS /chatgroup/:chatgroup_id/socket
	//
	// This fn is called before socket creation; its purpose is to check that the requested socket should be delivered.
	// We do this by inferring from the result from /api/v3/chatgroup/:chatgroup_id -- if the result includes members-only data,
	// we assume the user should be able to get updates to the members-only data.
	func shouldCreateChatGroupSocket(_ req: Request) async throws -> HTTPHeaders? {
		guard let lfgIDStr = req.parameters.get(chatGroupIDParam.paramString), let lfgID = UUID(uuidString: lfgIDStr) else {
			throw Abort(.unauthorized, reason: "Request parameter lfg_ID is missing")
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(lfgID)")
		let chatgroup = try response.content.decode(ChatGroupData.self)
		guard chatgroup.members != nil else {
			throw Abort(.unauthorized, reason: "Not authorized")
		}
		return HTTPHeaders()
	}

	// WS /chatgroup/:chatgroup_ID/socket
	//
	// Opens a WebSocket that receives updates on the given ChatGroup. This websocket is intended for use by the
	// web client and updates include HTML fragments ready for document insertion.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createGroupChatSocket(_ req: Request, _ ws: WebSocket) async {
		guard let user = try? req.auth.require(UserCacheData.self),
			let chatGroupID = req.parameters.get(chatGroupIDParam.paramString, as: UUID.self)
		else {
			try? await ws.close()
			return
		}
		// Note: This kind of breaks UI-API separation as it makes webSocketStore a structure that operates
		// at both levels.
		let userSocket = UserSocket(userID: user.userID, socket: ws, chatGroupID: chatGroupID, htmlOutput: true)
		try? req.webSocketStore.storeChatGroupSocket(userSocket)

		ws.onClose.whenComplete { result in
			try? req.webSocketStore.removeChatGroupSocket(userSocket)
		}
	}

	// POST /chatgroup/ID/post
	//
	// Post a message in a chatgroup.
	func chatGroupThreadPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/post", method: .POST, encodeContent: postContent)
		return .created
	}

	// POST /chatgroup/post/:chatGroupPost_ID/delete
	// DELETE /chatgroup/post/:chatGroupPost_ID
	//
	// Deletes a message posted in a chatgroup. Must be author or mod.
	func chatGroupPostDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/post/\(postID)", method: .DELETE)
		return response.status
	}

	// POST /chatgroup/ID/join
	//
	// Joins a chatgroup.
	func chatGroupJoinPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/join", method: .POST)
		return .created
	}

	// POST /chatgroup/ID/leave
	//
	// Leaves a chatgroup.
	func chatGroupLeavePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/unjoin", method: .POST)
		return .created
	}

	// POST /chatgroup/ID/cancel
	//
	// Cancels a chatgroup. Owner only.
	func chatGroupCancelPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/cancel", method: .POST)
		return .created
	}

	// GET /chatgroup/ID/members
	//
	// Allows the owner of a chatgroup to add/remove members.
	func chatGroupMembersPageHandler(_ req: Request) async throws -> View {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid chatgroup ID"
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)")
		let chatgroup = try response.content.decode(ChatGroupData.self)
		let ctx = try ChatGroupCreateUpdatePageContext(req, chatGroupToUpdate: chatgroup)
		return try await req.view.render("ChatGroup/chatGroupManageMembers", ctx)
	}

	// POST /chatgroup/chatgroup_ID/members/add/user_ID
	//
	// Allows a chatgroup owner to add a user to their chatgroup.
	func chatGroupAddUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/user/\(userID)/add", method: .POST)
		return .created
	}

	// POST /chatgroup/chatgroup_ID/members/remove/user_ID
	//
	// Allows a chatgroup owner to remove a user from their chatgroup.
	func chatGroupRemoveUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/user/\(userID)/remove", method: .POST)
		return .created
	}

	// GET /chatgroup/report/:chatgroup_ID
	//
	// Shows the page for reporting on a chatgroups' content. This reports on the ChatGroup itself, not individual posts.
	func chatGroupReportPageHandler(_ req: Request) async throws -> View {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		let ctx = try ReportPageContext(req, chatGroupID: chatGroupID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /chatgroup/report/ID
	//
	// Submits a report on a chatgroup.
	func chatGroupReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatGroupID = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing chatgroup_id")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/chatgroup/\(chatGroupID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// GET /chatgroup/post/report/:post_id
	//
	// Shows the report page for reporting on an individual post in a chatgroup.
	func chatGroupPostReportPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let ctx = try ReportPageContext(req, chatGroupPostID: postID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /chatgroup/post/report/:post_id
	//
	// Submits a completed report.
	func chatGroupPostReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/chatgroup/post/\(postID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// POST /chatgroup/:chatgroup_ID/delete
	// DELETE /chatgroup/:chatgroup_ID
	//
	// Deletes a chatgroup. Moderators only at the moment--owners may be able to delete, eventually.
	func chatGroupDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let chatgroup = req.parameters.get(chatGroupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "While deleting chatgroup: Invalid chatgroup ID"
		}
		let response = try await apiQuery(req, endpoint: "/chatgroup/\(chatgroup)", method: .DELETE)
		return response.status
	}
}
