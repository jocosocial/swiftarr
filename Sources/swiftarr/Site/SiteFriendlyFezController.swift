import Crypto
import FluentSQL
import Vapor

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

// Leaf context used in the Fez create, update, and memberlist pages
struct FezCreateUpdatePageContext: Encodable {
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
			trunk = .init(req, title: "Update Looking For Group", tab: .lfg)
			self.fez = fezToUpdate
			pageTitle = "Update Looking For Group"
			fezTitle = fez.title
			fezLocation = fez.location ?? ""
			fezType = fez.fezType.rawValue
			startTime = fez.startTime
			if let start = fez.startTime, let end = fez.endTime {
				minutes = Int(end.timeIntervalSince(start) / 60 + 0.01)  // should be 30, 60, 90, etc.
			}
			minPeople = fez.minParticipants
			maxPeople = fez.maxParticipants
			info = fez.info
			formAction = "/lfg/\(fez.fezID)/update"
			submitButtonTitle = "Update"
		}
		else {
			trunk = .init(req, title: "New Looking For Group", tab: .lfg)
			pageTitle = "Create a New LFG"
			formAction = "/lfg/create"
			minPeople = 2
			maxPeople = 2
		}
	}

	// Builds a Create Fez page for a fez, prefilled to play the indicated boardgame.
	// If `game` is an expansion set, you can optionally pass the baseGame in as well.
	init(_ req: Request, forGame game: BoardgameData, baseGame: BoardgameData? = nil) {
		trunk = .init(req, title: "New LFG", tab: .lfg)
		pageTitle = "Create LFG to play a Boardgame"
		fezTitle = "Play \(game.gameName)"
		fezLocation = "Dining Room, Deck 3 Aft"
		fezType = "gaming"
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
		formAction = "/lfg/create"
		submitButtonTitle = "Create"
	}
}

// Leaf context used in the Find, Joined and Owned Fez pages
struct FezListPageContext: Encodable {
	enum FezTab: String, Codable {
		case faq, find, joined, owned
	}
	
	struct QueryParams: Content {
		var type: String?
		var cruiseday: Int?
		var hidePast: Bool?
	}

	var trunk: TrunkContext
	var fezList: FezListData
	var paginator: PaginatorContext
	var tab: FezTab
	var dayList: [String]
	var typeSelection: String?
	var daySelection: Int?
	var hidePastSelection: Bool?

	init(_ req: Request, fezList: FezListData, tab: FezTab) throws {
		let params = try req.query.decode(QueryParams.self)
		var title: String
		var paginationPath: String
		switch tab {
			case .faq:
				title = "LFG Help"
				paginationPath = "/lfg"
			case .find: 
				title = "LFG Find Groups"
				paginationPath = "/lfg"
			case .joined: 
				title = "LFG Joined Groups"
				paginationPath = "/lfg/joined"
			case .owned: 
				title = "LFG Owned Groups"
				paginationPath = "/lfg/owned"
		}
		trunk = .init(req, title: title, tab: .lfg)
		let limit = fezList.paginator.limit
		var hidePastPaginationParam = ""
		if let hidePast = params.hidePast {
			hidePastPaginationParam = "&hidePast=\(hidePast)"
		}
		paginator = .init(fezList.paginator) { pageIndex in
			"\(paginationPath)?start=\(pageIndex * limit)&limit=\(limit)\(hidePastPaginationParam)"
		}
		self.fezList = fezList
		self.tab = tab
		typeSelection = params.type ?? "all"
		daySelection = params.cruiseday
		hidePastSelection = params.hidePast
		var cruiseDate = Calendar.current.date(from: Settings.shared.cruiseStartDateComponents)!
		let dayFormatter = DateFormatter()
		dayFormatter.setLocalizedDateFormatFromTemplate("E, MMM d")
		dayList = []
		for _ in 0..<Settings.shared.cruiseLengthInDays {
			dayList.append(dayFormatter.string(from: cruiseDate))
			cruiseDate = Calendar.current.date(byAdding: DateComponents(day: 1), to: cruiseDate)!
		}
	}
}

struct SiteFriendlyFezController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		let globalRoutes = getGlobalRoutes(app).grouped("lfg")
				.grouped(DisabledSiteSectionMiddleware(feature: .friendlyfez))
		globalRoutes.get("", use: fezRootPageHandler).destination("the Looking For Group list")
		globalRoutes.get("joined", use: joinedFezPageHandler).destination("the LFGs you've joined")
		globalRoutes.get("owned", use: ownedFezPageHandler).destination("the LFGs you've created")
		globalRoutes.get(fezIDParam, use: singleFezPageHandler).destination("this LFG")
		globalRoutes.get("faq", use: fezFAQHandler).destination("the LFG FAQ")

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("lfg")
				.grouped(DisabledSiteSectionMiddleware(feature: .friendlyfez))
		privateRoutes.get("create", use: fezCreatePageHandler)
		privateRoutes.get(fezIDParam, "update", use: fezUpdatePageHandler)
		privateRoutes.get(fezIDParam, "edit", use: fezUpdatePageHandler)
		privateRoutes.post("create", use: fezCreateOrUpdatePostHandler)
		privateRoutes.post(fezIDParam, "update", use: fezCreateOrUpdatePostHandler)

		privateRoutes.post(fezIDParam, "join", use: fezJoinPostHandler)
		privateRoutes.post(fezIDParam, "leave", use: fezLeavePostHandler)
		privateRoutes.post(fezIDParam, "post", use: fezThreadPostHandler)
		privateRoutes.post("post", postIDParam, "delete", use: fezPostDeleteHandler)
		privateRoutes.delete("post", postIDParam, use: fezPostDeleteHandler)
		privateRoutes.post(fezIDParam, "cancel", use: fezCancelPostHandler)
		privateRoutes.get(fezIDParam, "members", use: fezMembersPageHandler)
		privateRoutes.post(fezIDParam, "members", "add", userIDParam, use: fezAddUserPostHandler)
		privateRoutes.post(fezIDParam, "members", "remove", userIDParam, use: fezRemoveUserPostHandler)

		privateRoutes.get("report", fezIDParam, use: fezReportPageHandler)
		privateRoutes.post("report", fezIDParam, use: fezReportPostHandler)
		privateRoutes.get("post", "report", postIDParam, use: fezPostReportPageHandler)
		privateRoutes.post("post", "report", postIDParam, use: fezPostReportPostHandler)

		privateRoutes.webSocket(fezIDParam, "socket", shouldUpgrade: shouldCreateFezSocket, onUpgrade: createFezSocket)

		// Mods only
		privateRoutes.post(fezIDParam, "delete", use: fezDeleteHandler)
		privateRoutes.delete(fezIDParam, use: fezDeleteHandler)
	}

	// MARK: - FriendlyFez


	// GET /lfg
	// Shows the root Fez page, with a list of all fezzes.
	func fezRootPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/open")
		let fezList = try response.content.decode(FezListData.self)
		let ctx = try FezListPageContext(req, fezList: fezList, tab: .find)
		return try await req.view.render("Fez/fezRoot", ctx)
	}

	// GET /lfg/faq
	//
	// Shows a FAQ page for Fezzes.
	func fezFAQHandler(_ req: Request) async throws -> View {
		struct FezFAQPageContext: Encodable {
			var trunk: TrunkContext
			var tab: FezListPageContext.FezTab

			init(_ req: Request) throws {
				trunk = .init(req, title: "LFG Help", tab: .lfg)
				tab = .faq
			}
		}
		let ctx = try FezFAQPageContext(req)
		return try await req.view.render("Fez/fezFAQ", ctx)
	}

	// GET /lfg/joined
	//
	// Shows the Joined Fezzes page.
	func joinedFezPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/joined?excludetype=closed&excludetype=open")
		let fezList = try response.content.decode(FezListData.self)
		let ctx = try FezListPageContext(req, fezList: fezList, tab: .joined)
		return try await req.view.render("Fez/fezJoined", ctx)
	}

	// GET /lfg/owned
	//
	// Shows the Owned Fezzes page. These are the Fezzes a user has created.
	func ownedFezPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/fez/owner?excludetype=closed&excludetype=open")
		let fezList = try response.content.decode(FezListData.self)
		let ctx = try FezListPageContext(req, fezList: fezList, tab: .owned)
		return try await req.view.render("Fez/fezOwned", ctx)
	}

	// GET /lfg/create
	//
	// Shows the Create New Friendly Fez page
	func fezCreatePageHandler(_ req: Request) async throws -> View {
		let ctx = try FezCreateUpdatePageContext(req)
		return try await req.view.render("Fez/fezCreate", ctx)
	}

	// GET `/lfg/ID/update`
	// GET `/lfg/ID/edit`
	//
	// Shows the Update Friendly Fez page.
	func fezUpdatePageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid fez ID"
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(fezID)")
		let fez = try response.content.decode(FezData.self)
		let ctx = try FezCreateUpdatePageContext(req, fezToUpdate: fez)
		return try await req.view.render("Fez/fezCreate", ctx)
	}

	// POST /lfg/create
	// POST /lfg/ID/update
	// Handles the POST from either the Create Or Update Fez page
	func fezCreateOrUpdatePostHandler(_ req: Request) async throws -> HTTPStatus {
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
		let fezContentData = FezContentData(
			fezType: fezType,
			title: postStruct.subject,
			info: postStruct.postText,
			startTime: startTime,
			endTime: endTime,
			location: postStruct.location,
			minCapacity: postStruct.minimum,
			maxCapacity: postStruct.maximum,
			initialUsers: []
		)
		var path = "/fez/create"
		if let updatingFezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() {
			path = "/fez/\(updatingFezID)/update"
		}
		try await apiQuery(req, endpoint: path, method: .POST, encodeContent: fezContentData)
		return .created
	}

	// GET /lfg/ID
	//
	// Paginated.
	//
	// Shows a single Fez with all its posts.
	func singleFezPageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid fez ID"
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(fezID)")
		let fez = try response.content.decode(FezData.self)
		struct FezPageContext: Encodable {
			var trunk: TrunkContext
			var fez: FezData
			var userID: UUID
			var userIsMember: Bool  // TRUE if user is member
			var showModButton: Bool
			var oldPosts: [SocketFezPostData]  // Posts user has read already
			var showDivider: Bool  // TRUE if there a both old and new posts
			var newPosts: [SocketFezPostData]  // Posts user hasn't read.
			var post: MessagePostContext  // New post area
			var paginator: PaginatorContext  // For > 50 posts in thread.

			init(_ req: Request, fez: FezData) throws {
				let cacheUser = try req.auth.require(UserCacheData.self)
				trunk = .init(req, title: "\(fez.title) | LFG", tab: .lfg)
				self.fez = fez
				self.userID = cacheUser.userID
				userIsMember = false
				showModButton = trunk.userIsMod && ![.closed, .open].contains(fez.fezType)
				oldPosts = []
				newPosts = []
				showDivider = false
				post = .init(forType: .fezPost(fez))
				paginator = PaginatorContext(
					start: 0,
					total: 40,
					limit: 50,
					urlForPage: { pageIndex in
						"/lfg/\(fez.fezID)?start=\(pageIndex * 50)&limit=50"
					}
				)
				if let members = fez.members, let posts = members.posts, let paginator = members.paginator {
					self.userIsMember =
						members.participants.contains(where: { $0.userID == cacheUser.userID })
						|| members.waitingList.contains(where: { $0.userID == cacheUser.userID })
					for index in 0..<posts.count {
						let post = posts[index]
						if index < members.readCount {
							oldPosts.append(SocketFezPostData(post: post))
						}
						else {
							newPosts.append(SocketFezPostData(post: post))
						}
					}
					self.showDivider = oldPosts.count > 0 && newPosts.count > 0
					let limit = paginator.limit
					self.paginator = PaginatorContext(paginator) { pageIndex in
						"/fez/\(fez.fezID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
				}
			}
		}
		let ctx = try FezPageContext(req, fez: fez)
		return try await req.view.render("Fez/singleFez", ctx)
	}

	// WS /lfg/:fez_id/socket
	//
	// This fn is called before socket creation; its purpose is to check that the requested socket should be delivered.
	// We do this by inferring from the result from /api/v3/fez/:fez_id -- if the result includes members-only data,
	// we assume the user should be able to get updates to the members-only data.
	func shouldCreateFezSocket(_ req: Request) async throws -> HTTPHeaders? {
		guard let lfgIDStr = req.parameters.get(fezIDParam.paramString), let lfgID = UUID(uuidString: lfgIDStr) else {
			throw Abort(.unauthorized, reason: "Request parameter lfg_ID is missing")
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(lfgID)")
		let fez = try response.content.decode(FezData.self)
		guard fez.members != nil else {
			throw Abort(.unauthorized, reason: "Not authorized")
		}
		return HTTPHeaders()
	}

	// WS /lfg/:fez_ID/socket
	//
	// Opens a WebSocket that receives updates on the given Fez. This websocket is intended for use by the
	// web client and updates include HTML fragments ready for document insertion.
	// There are no messages intended to be sent from the client of this socket. Although this socket sends HTML for
	// new posts to the client, new posts *created* by the client should use the regular POST method.
	func createFezSocket(_ req: Request, _ ws: WebSocket) async {
		guard let user = try? req.auth.require(UserCacheData.self),
			let fezID = req.parameters.get(fezIDParam.paramString, as: UUID.self)
		else {
			try? await ws.close()
			return
		}
		// Note: This kind of breaks UI-API separation as it makes webSocketStore a structure that operates
		// at both levels.
		let userSocket = UserSocket(userID: user.userID, socket: ws, fezID: fezID, htmlOutput: true)
		try? req.webSocketStore.storeFezSocket(userSocket)

		ws.onClose.whenComplete { result in
			try? req.webSocketStore.removeFezSocket(userSocket)
		}
	}

	// POST /lfg/ID/post
	//
	// Post a message in a fez.
	func fezThreadPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		try await apiQuery(req, endpoint: "/fez/\(fezID)/post", method: .POST, encodeContent: postContent)
		return .created
	}

	// POST /lfg/post/:fezPost_ID/delete
	// DELETE /lfg/post/:fezPost_ID
	//
	// Deletes a message posted in a fez. Must be author or mod.
	func fezPostDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let response = try await apiQuery(req, endpoint: "/fez/post/\(postID)", method: .DELETE)
		return response.status
	}

	// POST /lfg/ID/join
	//
	// Joins a fez.
	func fezJoinPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		try await apiQuery(req, endpoint: "/fez/\(fezID)/join", method: .POST)
		return .created
	}

	// POST /lfg/ID/leave
	//
	// Leaves a fez.
	func fezLeavePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		try await apiQuery(req, endpoint: "/fez/\(fezID)/unjoin", method: .POST)
		return .created
	}

	// POST /lfg/ID/cancel
	//
	// Cancels a fez. Owner only.
	func fezCancelPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		try await apiQuery(req, endpoint: "/fez/\(fezID)/cancel", method: .POST)
		return .created
	}

	// GET /lfg/ID/members
	//
	// Allows the owner of a fez to add/remove members.
	func fezMembersPageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid fez ID"
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(fezID)")
		let fez = try response.content.decode(FezData.self)
		let ctx = try FezCreateUpdatePageContext(req, fezToUpdate: fez)
		return try await req.view.render("Fez/fezManageMembers", ctx)
	}

	// POST /lfg/fez_ID/members/add/user_ID
	//
	// Allows a fez owner to add a user to their fez.
	func fezAddUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
		try await apiQuery(req, endpoint: "/fez/\(fezID)/user/\(userID)/add", method: .POST)
		return .created
	}

	// POST /lfg/fez_ID/members/remove/user_ID
	//
	// Allows a fez owner to remove a user from their fez.
	func fezRemoveUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing user_id")
		}
		try await apiQuery(req, endpoint: "/fez/\(fezID)/user/\(userID)/remove", method: .POST)
		return .created
	}

	// GET /lfg/report/:fez_ID
	//
	// Shows the page for reporting on a fezzes' content. This reports on the Fez itself, not individual posts.
	func fezReportPageHandler(_ req: Request) async throws -> View {
		guard let fezID = req.parameters.get(fezIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let ctx = try ReportPageContext(req, fezID: fezID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /lfg/report/ID
	//
	// Submits a report on a fez.
	func fezReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fezID = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing fez_id")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/fez/\(fezID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// GET /lfg/post/report/:post_id
	//
	// Shows the report page for reporting on an individual post in a fez.
	func fezPostReportPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let ctx = try ReportPageContext(req, fezPostID: postID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /lfg/post/report/:post_id
	//
	// Submits a completed report.
	func fezPostReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/fez/post/\(postID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// POST /lfg/:fez_ID/delete
	// DELETE /lfg/:fez_ID
	//
	// Deletes a fez. Moderators only at the moment--owners may be able to delete, eventually.
	func fezDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let fez = req.parameters.get(fezIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "While deleting fez: Invalid fez ID"
		}
		let response = try await apiQuery(req, endpoint: "/fez/\(fez)", method: .DELETE)
		return response.status
	}
}
