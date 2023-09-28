import Crypto
import FluentSQL
import Vapor

// Form data from the Create/Update Group form
struct CreateGroupPostFormContent: Codable {
	var subject: String
	var location: String
	var eventtype: String
	var starttime: String
	var duration: Int
	var minimum: Int
	var maximum: Int
	var postText: String
}

struct GroupCreateUpdatePageContext: Encodable {
	var trunk: TrunkContext
	var group: GroupData?
	var pageTitle: String
	var groupTitle: String = ""
	var groupLocation: String = ""
	var groupType: String = ""
	var startTime: Date?
	var minutes: Int = 0
	var minPeople: Int = 0
	var maxPeople: Int = 0
	var info: String = ""
	var formAction: String
	var submitButtonTitle: String = "Create"

	init(_ req: Request, groupToUpdate: GroupData? = nil) throws {
		if let group = groupToUpdate {
			trunk = .init(req, title: "Update Looking For Group", tab: .lfg)
			self.group = groupToUpdate
			pageTitle = "Update Looking For Group"
			groupTitle = group.title
			groupLocation = group.location ?? ""
			groupType = group.groupType.rawValue
			startTime = group.startTime
			if let start = group.startTime, let end = group.endTime {
				minutes = Int(end.timeIntervalSince(start) / 60 + 0.01)  // should be 30, 60, 90, etc.
			}
			minPeople = group.minParticipants
			maxPeople = group.maxParticipants
			info = group.info
			formAction = "/group/\(group.groupID)/update"
			submitButtonTitle = "Update"
		}
		else {
			trunk = .init(req, title: "New Looking For Group", tab: .lfg)
			pageTitle = "Create a New LFG"
			formAction = "/group/create"
			minPeople = 2
			maxPeople = 2
		}
	}

	// Builds a Create Group page for a group, prefilled to play the indicated boardgame.
	// If `game` is an expansion set, you can optionally pass the baseGame in as well.
	init(_ req: Request, forGame game: BoardgameData, baseGame: BoardgameData? = nil) {
		trunk = .init(req, title: "New LFG", tab: .lfg)
		pageTitle = "Create LFG to play a Boardgame"
		groupTitle = "Play \(game.gameName)"
		groupLocation = "Dining Room, Deck 3 Aft"
		groupType = "gaming"
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
		formAction = "/group/create"
		submitButtonTitle = "Create"
	}
}

struct SiteFriendlyGroupController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		let globalRoutes = getGlobalRoutes(app).grouped("group")
			.grouped(DisabledSiteSectionMiddleware(feature: .friendlygroup))
		globalRoutes.get("", use: groupRootPageHandler)
		globalRoutes.get("joined", use: joinedGroupPageHandler)
		globalRoutes.get("owned", use: ownedGroupPageHandler)
		globalRoutes.get(groupIDParam, use: singleGroupPageHandler)
		globalRoutes.get("faq", use: groupFAQHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("group")
			.grouped(DisabledSiteSectionMiddleware(feature: .friendlygroup))
		privateRoutes.get("create", use: groupCreatePageHandler)
		privateRoutes.get(groupIDParam, "update", use: groupUpdatePageHandler)
		privateRoutes.get(groupIDParam, "edit", use: groupUpdatePageHandler)
		privateRoutes.post("create", use: groupCreateOrUpdatePostHandler)
		privateRoutes.post(groupIDParam, "update", use: groupCreateOrUpdatePostHandler)

		privateRoutes.post(groupIDParam, "join", use: groupJoinPostHandler)
		privateRoutes.post(groupIDParam, "leave", use: groupLeavePostHandler)
		privateRoutes.post(groupIDParam, "post", use: groupThreadPostHandler)
		privateRoutes.post("post", postIDParam, "delete", use: groupPostDeleteHandler)
		privateRoutes.delete("post", postIDParam, use: groupPostDeleteHandler)
		privateRoutes.post(groupIDParam, "cancel", use: groupCancelPostHandler)
		privateRoutes.get(groupIDParam, "members", use: groupMembersPageHandler)
		privateRoutes.post(groupIDParam, "members", "add", userIDParam, use: groupAddUserPostHandler)
		privateRoutes.post(groupIDParam, "members", "remove", userIDParam, use: groupRemoveUserPostHandler)

		privateRoutes.get("report", groupIDParam, use: groupReportPageHandler)
		privateRoutes.post("report", groupIDParam, use: groupReportPostHandler)
		privateRoutes.get("post", "report", postIDParam, use: groupPostReportPageHandler)
		privateRoutes.post("post", "report", postIDParam, use: groupPostReportPostHandler)

		privateRoutes.webSocket(groupIDParam, "socket", shouldUpgrade: shouldCreateGroupSocket, onUpgrade: createGroupSocket)

		// Mods only
		privateRoutes.post(groupIDParam, "delete", use: groupDeleteHandler)
		privateRoutes.delete(groupIDParam, use: groupDeleteHandler)
	}

	// MARK: - FriendlyGroup

	enum GroupTab: String, Codable {
		case faq, find, joined, owned
	}

	// GET /group
	// Shows the root Group page, with a list of all groups.
	func groupRootPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/group/open")
		let groupList = try response.content.decode(GroupListData.self)
		struct GroupRootPageContext: Encodable {
			var trunk: TrunkContext
			var groupList: GroupListData
			var paginator: PaginatorContext
			var tab: GroupTab
			var typeSelection: String?
			var daySelection: Int?
			var hidePastSelection: Bool?

			init(_ req: Request, groupList: GroupListData) throws {
				trunk = .init(req, title: "Looking For Group", tab: .lfg)
				self.groupList = groupList
				tab = .find
				typeSelection = req.query[String.self, at: "type"] ?? "all"
				daySelection = req.query[Int.self, at: "cruiseday"]
				let hidePastQuery = req.query[String.self, at: "hidePast"]
				hidePastSelection = hidePastQuery == nil ? nil : hidePastQuery?.lowercased() == "true"
				let limit = groupList.paginator.limit
				paginator = .init(groupList.paginator) { pageIndex in
					"/group?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try GroupRootPageContext(req, groupList: groupList)
		return try await req.view.render("Group/groupRoot", ctx)
	}

	// GET /group/faq
	//
	// Shows a FAQ page for Groups.
	func groupFAQHandler(_ req: Request) async throws -> View {
		struct GroupFAQPageContext: Encodable {
			var trunk: TrunkContext
			var tab: GroupTab

			init(_ req: Request) throws {
				trunk = .init(req, title: "Looking For Group", tab: .lfg)
				tab = .faq
			}
		}
		let ctx = try GroupFAQPageContext(req)
		return try await req.view.render("Group/groupFAQ", ctx)
	}

	// GET /group/joined
	//
	// Shows the Joined Groups page.
	func joinedGroupPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/group/joined?excludetype=closed&excludetype=open")
		let groupList = try response.content.decode(GroupListData.self)
		struct JoinedGroupPageContext: Encodable {
			var trunk: TrunkContext
			var groupList: GroupListData
			var paginator: PaginatorContext
			var tab: GroupTab
			var typeSelection: String?
			var daySelection: Int?
			var hidePastSelection: Bool?

			init(_ req: Request, groupList: GroupListData) throws {
				trunk = .init(req, title: "LFG Joined Groups", tab: .lfg)
				self.groupList = groupList
				tab = .joined
				typeSelection = req.query[String.self, at: "type"] ?? "all"
				daySelection = req.query[Int.self, at: "cruiseday"]
				let hidePastQuery = req.query[String.self, at: "hidePast"]
				hidePastSelection = hidePastQuery == nil ? nil : hidePastQuery?.lowercased() == "true"
				let limit = groupList.paginator.limit
				paginator = .init(groupList.paginator) { pageIndex in
					"/group/joined?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try JoinedGroupPageContext(req, groupList: groupList)
		return try await req.view.render("Group/groupJoined", ctx)
	}

	// GET /group/owned
	//
	// Shows the Owned Groups page. These are the Groups a user has created.
	func ownedGroupPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/group/owner?excludetype=closed&excludetype=open")
		let groupList = try response.content.decode(GroupListData.self)
		struct OwnedGroupPageContext: Encodable {
			var trunk: TrunkContext
			var groupList: GroupListData
			var paginator: PaginatorContext
			var tab: GroupTab
			var typeSelection: String?
			var daySelection: Int?
			var hidePastSelection: Bool?

			init(_ req: Request, groupList: GroupListData) throws {
				trunk = .init(req, title: "LFGs Created By You", tab: .lfg)
				self.groupList = groupList
				tab = .owned
				typeSelection = req.query[String.self, at: "type"] ?? "all"
				daySelection = req.query[Int.self, at: "cruiseday"]
				let hidePastQuery = req.query[String.self, at: "hidePast"]
				hidePastSelection = hidePastQuery == nil ? nil : hidePastQuery?.lowercased() == "true"
				let limit = groupList.paginator.limit
				paginator = .init(groupList.paginator) { pageIndex in
					"/group/joined?start=\(pageIndex * limit)&limit=\(limit)"
				}
			}
		}
		let ctx = try OwnedGroupPageContext(req, groupList: groupList)
		return try await req.view.render("Group/groupOwned", ctx)
	}

	// GET /group/create
	//
	// Shows the Create New Friendly Group page
	func groupCreatePageHandler(_ req: Request) async throws -> View {
		let ctx = try GroupCreateUpdatePageContext(req)
		return try await req.view.render("Group/groupCreate", ctx)
	}

	// GET `/group/ID/update`
	// GET `/group/ID/edit`
	//
	// Shows the Update Friendly Group page.
	func groupUpdatePageHandler(_ req: Request) async throws -> View {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid group ID"
		}
		let response = try await apiQuery(req, endpoint: "/group/\(groupID)")
		let group = try response.content.decode(GroupData.self)
		let ctx = try GroupCreateUpdatePageContext(req, groupToUpdate: group)
		return try await req.view.render("Group/groupCreate", ctx)
	}

	// POST /group/create
	// POST /group/ID/update
	// Handles the POST from either the Create Or Update Group page
	func groupCreateOrUpdatePostHandler(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(CreateGroupPostFormContent.self)
		var groupType: GroupType
		switch postStruct.eventtype {
		case "activity": groupType = .activity
		case "dining": groupType = .dining
		case "gaming": groupType = .gaming
		case "meetup": groupType = .meetup
		case "music": groupType = .music
		case "ashore": groupType = .shore
		default: groupType = .other
		}
		guard let startTime = dateFromW3DatetimeString(postStruct.starttime) else {
			throw Abort(.badRequest, reason: "Couldn't parse start time")
		}
		let endTime = startTime.addingTimeInterval(TimeInterval(postStruct.duration) * 60.0)
		let groupContentData = GroupContentData(
			groupType: groupType,
			title: postStruct.subject,
			info: postStruct.postText,
			startTime: startTime,
			endTime: endTime,
			location: postStruct.location,
			minCapacity: postStruct.minimum,
			maxCapacity: postStruct.maximum,
			initialUsers: []
		)
		var path = "/group/create"
		if let updatingGroupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() {
			path = "/group/\(updatingGroupID)/update"
		}
		try await apiQuery(req, endpoint: path, method: .POST, encodeContent: groupContentData)
		return .created
	}

	// GET /group/ID
	//
	// Paginated.
	//
	// Shows a single Group with all its posts.
	func singleGroupPageHandler(_ req: Request) async throws -> View {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid group ID"
		}
		let response = try await apiQuery(req, endpoint: "/group/\(groupID)")
		let group = try response.content.decode(GroupData.self)
		struct GroupPageContext: Encodable {
			var trunk: TrunkContext
			var group: GroupData
			var userID: UUID
			var userIsMember: Bool  // TRUE if user is member
			var showModButton: Bool
			var oldPosts: [SocketGroupPostData]  // Posts user has read already
			var showDivider: Bool  // TRUE if there a both old and new posts
			var newPosts: [SocketGroupPostData]  // Posts user hasn't read.
			var post: MessagePostContext  // New post area
			var paginator: PaginatorContext  // For > 50 posts in thread.

			init(_ req: Request, group: GroupData) throws {
				let cacheUser = try req.auth.require(UserCacheData.self)
				trunk = .init(req, title: "LFG", tab: .lfg)
				self.group = group
				self.userID = cacheUser.userID
				userIsMember = false
				showModButton = trunk.userIsMod && ![.closed, .open].contains(group.groupType)
				oldPosts = []
				newPosts = []
				showDivider = false
				post = .init(forType: .groupPost(group))
				paginator = PaginatorContext(
					start: 0,
					total: 40,
					limit: 50,
					urlForPage: { pageIndex in
						"/group/\(group.groupID)?start=\(pageIndex * 50)&limit=50"
					}
				)
				if let members = group.members, let posts = members.posts, let paginator = members.paginator {
					self.userIsMember =
						members.participants.contains(where: { $0.userID == cacheUser.userID })
						|| members.waitingList.contains(where: { $0.userID == cacheUser.userID })
					for index in 0..<posts.count {
						let post = posts[index]
						if index < members.readCount {
							oldPosts.append(SocketGroupPostData(post: post))
						}
						else {
							newPosts.append(SocketGroupPostData(post: post))
						}
					}
					self.showDivider = oldPosts.count > 0 && newPosts.count > 0
					let limit = paginator.limit
					self.paginator = PaginatorContext(paginator) { pageIndex in
						"/group/\(group.groupID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
				}
			}
		}
		let ctx = try GroupPageContext(req, group: group)
		return try await req.view.render("Group/singleGroup", ctx)
	}

	// WS /group/:group_id/socket
	//
	// This fn is called before socket creation; its purpose is to check that the requested socket should be delivered.
	// We do this by inferring from the result from /api/v3/group/:group_id -- if the result includes members-only data,
	// we assume the user should be able to get updates to the members-only data.
	func shouldCreateGroupSocket(_ req: Request) async throws -> HTTPHeaders? {
		guard let lfgIDStr = req.parameters.get(groupIDParam.paramString), let lfgID = UUID(uuidString: lfgIDStr) else {
			throw Abort(.unauthorized, reason: "Request parameter lfg_ID is missing")
		}
		let response = try await apiQuery(req, endpoint: "/group/\(lfgID)")
		let group = try response.content.decode(GroupData.self)
		guard group.members != nil else {
			throw Abort(.unauthorized, reason: "Not authorized")
		}
		return HTTPHeaders()
	}

	// WS /group/:group_ID/socket
	//
	// Opens a WebSocket that receives updates on the given Group. This websocket is intended for use by the
	// web client and updates include HTML fragments ready for document insertion.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createGroupSocket(_ req: Request, _ ws: WebSocket) async {
		guard let user = try? req.auth.require(UserCacheData.self),
			let groupID = req.parameters.get(groupIDParam.paramString, as: UUID.self)
		else {
			try? await ws.close()
			return
		}
		// Note: This kind of breaks UI-API separation as it makes webSocketStore a structure that operates
		// at both levels.
		let userSocket = UserSocket(userID: user.userID, socket: ws, groupID: groupID, htmlOutput: true)
		try? req.webSocketStore.storeGroupSocket(userSocket)

		ws.onClose.whenComplete { result in
			try? req.webSocketStore.removeGroupSocket(userSocket)
		}
	}

	// POST /group/ID/post
	//
	// Post a message in a group.
	func groupThreadPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		try await apiQuery(req, endpoint: "/group/\(groupID)/post", method: .POST, encodeContent: postContent)
		return .created
	}

	// POST /group/post/:groupPost_ID/delete
	// DELETE /group/post/:groupPost_ID
	//
	// Deletes a message posted in a group. Must be author or mod.
	func groupPostDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		let response = try await apiQuery(req, endpoint: "/group/post/\(postID)", method: .DELETE)
		return response.status
	}

	// POST /group/ID/join
	//
	// Joins a group.
	func groupJoinPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		try await apiQuery(req, endpoint: "/group/\(groupID)/join", method: .POST)
		return .created
	}

	// POST /group/ID/leave
	//
	// Leaves a group.
	func groupLeavePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		try await apiQuery(req, endpoint: "/group/\(groupID)/unjoin", method: .POST)
		return .created
	}

	// POST /group/ID/cancel
	//
	// Cancels a group. Owner only.
	func groupCancelPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		try await apiQuery(req, endpoint: "/group/\(groupID)/cancel", method: .POST)
		return .created
	}

	// GET /group/ID/members
	//
	// Allows the owner of a group to add/remove members.
	func groupMembersPageHandler(_ req: Request) async throws -> View {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid group ID"
		}
		let response = try await apiQuery(req, endpoint: "/group/\(groupID)")
		let group = try response.content.decode(GroupData.self)
		let ctx = try GroupCreateUpdatePageContext(req, groupToUpdate: group)
		return try await req.view.render("Group/groupManageMembers", ctx)
	}

	// POST /group/group_ID/members/add/user_ID
	//
	// Allows a group owner to add a user to their group.
	func groupAddUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
		try await apiQuery(req, endpoint: "/group/\(groupID)/user/\(userID)/add", method: .POST)
		return .created
	}

	// POST /group/group_ID/members/remove/user_ID
	//
	// Allows a group owner to remove a user from their group.
	func groupRemoveUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
		try await apiQuery(req, endpoint: "/group/\(groupID)/user/\(userID)/remove", method: .POST)
		return .created
	}

	// GET /group/report/:group_ID
	//
	// Shows the page for reporting on a groups' content. This reports on the Group itself, not individual posts.
	func groupReportPageHandler(_ req: Request) async throws -> View {
		guard let groupID = req.parameters.get(groupIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		let ctx = try ReportPageContext(req, groupID: groupID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /group/report/ID
	//
	// Submits a report on a group.
	func groupReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let groupID = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing group_id")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/group/\(groupID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// GET /group/post/report/:post_id
	//
	// Shows the report page for reporting on an individual post in a group.
	func groupPostReportPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let ctx = try ReportPageContext(req, groupPostID: postID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /group/post/report/:post_id
	//
	// Submits a completed report.
	func groupPostReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/group/post/\(postID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// POST /group/:group_ID/delete
	// DELETE /group/:group_ID
	//
	// Deletes a group. Moderators only at the moment--owners may be able to delete, eventually.
	func groupDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let group = req.parameters.get(groupIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "While deleting group: Invalid group ID"
		}
		let response = try await apiQuery(req, endpoint: "/group/\(group)", method: .DELETE)
		return response.status
	}
}
