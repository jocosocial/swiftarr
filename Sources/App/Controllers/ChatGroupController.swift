import Crypto
import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/chatgroup/*` route endpoints and handler functions related to Looking For Group and Seamail chats.
struct ChatGroupController: APIRouteCollection {

	// A struct with common URL query parameters for routes in the ChatGroup Controller.
	// Most route handlers don't actually use all these options; each handler's header comment
	// specifies what URL options it uses.
	// The decode() call decodes the URL Query into this struct; trying to decode keys the the handler doesn't use
	// doesn't matter; whether or not the URL Query contains the option or not. However, it is possible a malformed
	// but unused query parameter would result in an error for the call.
	struct ChatGroupURLQueryStruct: Content {
		var type: [String]
		var excludetype: [String]
		var onlynew: Bool?
		var start: Int?
		var limit: Int?
		var cruiseDay: Int?
		var search: String?
		var hidePast: Bool?

		func getTypes() throws -> [ChatGroupType]? {
			let includeTypes = try type.map { try ChatGroupType.fromAPIString($0) }
			return includeTypes.count > 0 ? includeTypes : nil
		}

		func getExcludeTypes() throws -> [ChatGroupType]? {
			let excludeTypes = try excludetype.map { try ChatGroupType.fromAPIString($0) }
			return excludeTypes.count > 0 ? excludeTypes : nil
		}

		func calcStart() -> Int {
			return start ?? 0
		}

		func calcLimit() -> Int {
			return (limit ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		}

		// Used for: dbQuery.range(urlQuery.calcRange())
		func calcRange() -> Range<Int> {
			let rangeStart = calcStart()
			return rangeStart..<(rangeStart + calcLimit())
		}
	}

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/chatgroup endpoints
		let chatGroupRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .chatgroup)).grouped("api", "v3", "chatgroup")

		// Open access routes
		chatGroupRoutes.get("types", use: typesHandler)

		// endpoints available only when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: chatGroupRoutes)
		tokenCacheAuthGroup.get("open", use: openHandler)
		tokenCacheAuthGroup.get("joined", use: joinedHandler)
		tokenCacheAuthGroup.get("owner", use: ownerHandler)
		tokenCacheAuthGroup.get(chatGroupIDParam, use: chatGroupHandler)
		tokenCacheAuthGroup.post("create", use: createHandler)
		tokenCacheAuthGroup.on(.POST, chatGroupIDParam, "post", body: .collect(maxSize: "30mb"), use: postAddHandler)
		tokenCacheAuthGroup.webSocket(chatGroupIDParam, "socket", onUpgrade: createGroupChatSocket)
		tokenCacheAuthGroup.post(chatGroupIDParam, "cancel", use: cancelHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "join", use: joinHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "unjoin", use: unjoinHandler)
		tokenCacheAuthGroup.post("post", chatGroupPostIDParam, "delete", use: postDeleteHandler)
		tokenCacheAuthGroup.delete("post", chatGroupPostIDParam, use: postDeleteHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "user", userIDParam, "add", use: userAddHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "user", userIDParam, "remove", use: userRemoveHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "update", use: updateHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "delete", use: chatGroupDeleteHandler)
		tokenCacheAuthGroup.delete(chatGroupIDParam, use: chatGroupDeleteHandler)
		tokenCacheAuthGroup.post(chatGroupIDParam, "report", use: reportChatGroupHandler)
		tokenCacheAuthGroup.post("post", chatGroupPostIDParam, "report", use: reportChatGroupPostHandler)

	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

	// MARK: Retrieving ChatGroups

	/// `/GET /api/v3/chatgroup/types`
	///
	/// Retrieve a list of all values for `ChatGroupType` as strings.
	///
	/// - Returns: An array of `String` containing the `.label` value for each type.
	func typesHandler(_ req: Request) throws -> [String] {
		return ChatGroupType.allCases.map { $0.label }
	}

	/// `GET /api/v3/chatgroup/open`
	///
	/// Retrieve ChatGroups with open slots and a startTime of no earlier than one hour ago. Results are returned sorted by start time, then by title.
	///
	/// **URL Query Parameters:**
	///
	/// * `?cruiseday=INT` - Only return chatgroups occuring on this day of the cruise. Embarkation Day is day 0.
	/// * `?type=STRING` - Only return chatgroups of this type, there STRING is a `ChatGroupType.fromAPIString()` string.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of chatgroups to return; defaults to 50.
	/// - `?hidepast=BOOLEAN` - Show chatgroups that started more than one hour in the past. For this endpoint, this defaults to TRUE.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `ChatGroupData` containing current chatgroups with open slots.
	func openHandler(_ req: Request) async throws -> ChatGroupListData {
		let urlQuery = try req.query.decode(ChatGroupURLQueryStruct.self)
		let cacheUser = try req.auth.require(UserCacheData.self)

		let chatGroupQuery = ChatGroup.query(on: req.db)
			.filter(\.$chatGroupType !~ [.closed, .open])
			.filter(\.$owner.$id !~ cacheUser.getBlocks())
			.filter(\.$cancelled == false)

		if urlQuery.hidePast ?? true {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			chatGroupQuery.filter(\.$startTime > searchStartTime)
		}

		if let typeFilter = try urlQuery.getTypes() {
			chatGroupQuery.filter(\.$chatGroupType ~~ typeFilter)
		}
		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			let threeAMCutoff =
				portCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate())
				?? Settings.shared.cruiseStartDate()
			let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: threeAMCutoff) ?? threeAMCutoff
			let dayEnd = portCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
			chatGroupQuery.filter(\.$startTime >= dayStart).filter(\.$startTime < dayEnd)
		}
		let groupChatCount = try await chatGroupQuery.count()
		let chatgroups = try await chatGroupQuery.sort(\.$startTime, .ascending).sort(\.$title, .ascending)
			.range(urlQuery.calcRange()).all()
		let chatGroupDataArray: [ChatGroupData] = try chatgroups.compactMap { chatgroup in
			// ChatGroups are only 'open' if their waitlist is < 1/2 the size of their capacity. A chatgroup with a max of 10 people
			// could have a waitlist of 5, then it stops showing up in 'open' searches.
			if (chatgroup.maxCapacity == 0 || chatgroup.participantArray.count < Int(Double(chatgroup.maxCapacity) * 1.5))
				&& !chatgroup.participantArray.contains(cacheUser.userID)
			{
				return try buildChatGroupData(from: chatgroup, with: nil, for: cacheUser, on: req)
			}
			return nil
		}
		return ChatGroupListData(
			paginator: Paginator(total: groupChatCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()),
			chatgroups: chatGroupDataArray
		)
	}

	/// `GET /api/v3/chatgroup/joined`
	///
	/// Retrieve all the ChatGroup chats that the user has joined. Results are sorted by descending chatgroup update time.
	///
	/// **Query Parameters:**
	/// * `?cruiseday=INT` - Only return chatgroups occuring on this day of the cruise. Embarkation Day is day 0.
	/// - `?type=STRING` - Only return chatgroups of the given chatGroupType. See `ChatGroupType` for a list.
	/// - `?excludetype=STRING` - Don't return chatgroups of the given type. See `ChatGroupType` for a list.
	/// - `?onlynew=TRUE` - Only return chatgroups with unread messages.
	/// - `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// - `?limit=INT` - The maximum number of chatgroups to return; defaults to 50.
	/// - `?search=STRING` - Only show chatgroups whose title, info, or any post contains the given string.
	/// - `?hidepast=BOOLEAN` - Hide chatgroups that started more than one hour in the past. For this endpoint, this defaults to FALSE.
	///
	/// Moderators and above can use the `foruser` query parameter to access pseudo-accounts:
	///
	/// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	///
	/// `/GET /api/v3/chatgroup/types` is  the canonical way to get the list of acceptable values. Type and excludetype are exclusive options, obv.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `ChatGroupData` containing all the chatgroups joined by the user.
	func joinedHandler(_ req: Request) async throws -> ChatGroupListData {
		let urlQuery = try req.query.decode(ChatGroupURLQueryStruct.self)
		let cacheUser = try req.auth.require(UserCacheData.self)
		let effectiveUser = try getEffectiveUser(user: cacheUser, req: req)
		let query = ChatGroupParticipant.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.join(ChatGroup.self, on: \ChatGroupParticipant.$chatGroup.$id == \ChatGroup.$id)
		if let includeTypes = try urlQuery.getTypes() {
			query.filter(ChatGroup.self, \.$chatGroupType ~~ includeTypes)
		}
		else if let excludeTypes = try urlQuery.getExcludeTypes() {
			query.filter(ChatGroup.self, \.$chatGroupType !~ excludeTypes)
		}

		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			let threeAMCutoff =
				portCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate())
				?? Settings.shared.cruiseStartDate()
			let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: threeAMCutoff) ?? threeAMCutoff
			let dayEnd = portCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
			query.filter(ChatGroup.self, \.$startTime >= dayStart).filter(ChatGroup.self, \.$startTime < dayEnd)
		}

		if urlQuery.hidePast ?? false {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			query.filter(ChatGroup.self, \.$startTime > searchStartTime)
		}

		if let onlyNew = urlQuery.onlynew {
			// Uses a custom filter to test "readCount + hiddenCount < ChatGroup.postCount". If true, there's unread messages
			// in this chat. Because it uses a custom filter for parameter 1, the other params use the weird long-form notation.
			query.filter(
				DatabaseQuery.Field.custom("\(ChatGroupParticipant().$readCount.key) + \(ChatGroupParticipant().$hiddenCount.key)"),
				onlyNew ? DatabaseQuery.Filter.Method.lessThan : DatabaseQuery.Filter.Method.equal,
				DatabaseQuery.Field.path(ChatGroup.path(for: \.$postCount), schema: ChatGroup.schema)
			)
		}
		if var searchStr = urlQuery.search {
			searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			query.join(ChatGroupPost.self, on: \ChatGroupPost.$chatGroup.$id == \ChatGroup.$id, method: .left)
			query.group(.or) { group in
				group.fullTextFilter(ChatGroupPost.self, \.$text, searchStr)
					.fullTextFilter(ChatGroup.self, \.$title, searchStr)
					.fullTextFilter(ChatGroup.self, \.$info, searchStr)
			}
			// We joined ChatGroupPost above, but we need to exclude its fields from the result set to prevent duplicates
			query.fields(for: ChatGroupParticipant.self).fields(for: ChatGroup.self).unique()
		}
		async let groupChatCount = try query.count()
		async let pivots = query.sort(ChatGroup.self, \.$updatedAt, .descending).range(urlQuery.calcRange()).all()
		let chatGroupDataArray = try await pivots.map { pivot -> ChatGroupData in
			let chatgroup = try pivot.joined(ChatGroup.self)
			return try buildChatGroupData(from: chatgroup, with: pivot, for: effectiveUser, on: req)
		}
		return try await ChatGroupListData(
			paginator: Paginator(total: groupChatCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()),
			chatgroups: chatGroupDataArray
		)
	}

	/// `GET /api/v3/chatgroup/owner`
	///
	/// Retrieve the ChatGroup chats created by the user.
	///
	/// - Note: There is no block filtering on this endpoint. In theory, a block could only
	///   apply if it were set *after* the chatgroup had been joined by the second party. The
	///   owner of the chatgroup has the ability to remove users if desired, and the chatgroup itself is no
	///   longer visible to the non-owning party.
	///
	/// **Query Parameters:**
	/// * `?cruiseday=INT` - Only return chatgroups occuring on this day of the cruise. Embarkation Day is day 0.
	/// - `?type=STRING` - Only return chatgroups of the given chatGroupType. See `ChatGroupType` for a list.
	/// - `?excludetype=STRING` - Don't return chatgroups of the given type. See `ChatGroupType` for a list.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of chatgroups to return; defaults to 50.
	/// - `?hidepast=BOOLEAN` - Hide chatgroups that started more than one hour in the past. For this endpoint, this defaults to FALSE.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `ChatGroupData` containing all the chatgroups created by the user.
	func ownerHandler(_ req: Request) async throws -> ChatGroupListData {
		let urlQuery = try req.query.decode(ChatGroupURLQueryStruct.self)
		let user = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = ChatGroup.query(on: req.db).filter(\.$owner.$id == user.userID)
			.join(ChatGroupParticipant.self, on: \ChatGroupParticipant.$chatGroup.$id == \ChatGroup.$id)
			.filter(ChatGroupParticipant.self, \.$user.$id == user.userID)
		if let includeTypes = try urlQuery.getTypes() {
			query.filter(\.$chatGroupType ~~ includeTypes)
		}
		else if let excludeTypes = try urlQuery.getExcludeTypes() {
			query.filter(\.$chatGroupType !~ excludeTypes)
		}

		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			let threeAMCutoff =
				portCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate())
				?? Settings.shared.cruiseStartDate()
			let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: threeAMCutoff) ?? threeAMCutoff
			let dayEnd = portCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
			query.filter(\.$startTime >= dayStart).filter(\.$startTime < dayEnd)
		}

		if urlQuery.hidePast ?? false {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			query.filter(\.$startTime > searchStartTime)
		}

		// get owned chatgroups
		async let groupChatCount = query.count()
		async let chatgroups = query.range(start..<(start + limit)).sort(\.$createdAt, .descending).all()
		// convert to ChatGroupData
		let chatGroupDataArray = try await chatgroups.map { (chatgroup) -> ChatGroupData in
			let userParticipant = try chatgroup.joined(ChatGroupParticipant.self)
			return try buildChatGroupData(from: chatgroup, with: userParticipant, for: user, on: req)
		}
		return try await ChatGroupListData(
			paginator: Paginator(total: groupChatCount, start: start, limit: limit),
			chatgroups: chatGroupDataArray
		)
	}

	/// `GET /api/v3/chatgroup/:chatgroup_ID`
	///
	/// Retrieve information about the specified ChatGroup. For users that aren't members of the chatgroup, this info will be the same as
	/// the info returned for `GET /api/v3/chatgroup/open`. For users that have joined the chatgroup the `ChatGroupData.MembersOnlyData` will be populated, as will
	/// the `ChatGroupPost`s.
	///
	/// **Query Parameters:**
	/// * `?start=INT` - The offset to the first post to return in the array of posts.
	/// * `?limit=INT` - The maximum number of posts to return; defaults to 50.
	///
	/// Start and limit only have an effect when the user is a member of the ChatGroup. Limit defaults to 50 and start defaults to `(readCount / limit) * limit`,
	/// where readCount is how many posts the user has read already.
	///
	/// Moderators and above can use the `foruser` query parameter to access pseudo-accounts:
	///
	/// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	///
	/// When a member calls this method, it updates the member's `readCount`, marking all posts read up to `start + limit`.
	/// However, the returned readCount is the value before updating. If there's 5 posts in the chat, and the member has read 3 of them, the returned
	/// `ChatGroupData` has 5 posts, we return 3 in `ChatGroupData.readCount`field, and update the pivot's readCount to 5.
	///
	/// `ChatGroupPost`s are ordered by creation time.
	///
	/// - Note: Posts are subject to block and mute user filtering, but mutewords are ignored
	///   in order to not suppress potentially important information.
	///
	/// - Parameter chatGroupID: in the URL path.
	/// - Throws: 404 error if a block between the user and chatgroup owner applies. A 5xx response
	///   should be reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` with chatgroup info and all discussion posts.
	func chatGroupHandler(_ req: Request) async throws -> ChatGroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		let effectiveUser = getEffectiveUser(user: cacheUser, req: req, chatgroup: chatgroup)
		guard !cacheUser.getBlocks().contains(chatgroup.$owner.id) else {
			throw Abort(.notFound, reason: "this \(chatgroup.chatGroupType.lfgLabel) is not available")
		}
		let pivot = try await chatgroup.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.first()
		var chatGroupData = try buildChatGroupData(from: chatgroup, with: pivot, for: cacheUser, on: req)
		if let _ = chatGroupData.members {
			let (posts, paginator) = try await buildPostsForChatGroup(chatgroup, pivot: pivot, on: req, user: cacheUser)
			chatGroupData.members?.paginator = paginator
			chatGroupData.members?.posts = posts
		}
		return chatGroupData
	}

	// MARK: Membership

	/// `POST /api/v3/chatgroup/ID/join`
	///
	/// Add the current user to the ChatGroup. If the `.maxCapacity` of the chatgroup has been
	/// reached, the user is added to the waiting list.
	///
	/// - Note: A user cannot join a chatgroup that is owned by a blocked or blocking user. If any
	///   current participating or waitList user is in the user's blocks, their identity is
	///   replaced by a placeholder in the returned data. It is the user's responsibility to
	///   examine the participant list for conflicts prior to joining or attending.
	///
	/// - Parameter chatGroupID: in the URL path.
	/// - Throws: 400 error if the supplied ID is not a chatgroup barrel or user is already in chatgroup.
	///   404 error if a block between the user and chatgroup owner applies. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` containing the updated chatgroup data.
	func joinHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard chatgroup.chatGroupType != .closed else {
			throw Abort(.badRequest, reason: "Cannot add members to a closed chat")
		}
		guard chatgroup.chatGroupType != .open else {
			throw Abort(.badRequest, reason: "Cannot add youself to a Seamail chat. Ask the chat creator to add you.")
		}
		guard !chatgroup.participantArray.contains(cacheUser.userID) else {
			throw Abort(.notFound, reason: "user is already a member of this \(chatgroup.chatGroupType.lfgLabel)")
		}
		// respect blocks
		guard !cacheUser.getBlocks().contains(chatgroup.$owner.id) else {
			throw Abort(.notFound, reason: "This \(chatgroup.chatGroupType.lfgLabel) is not available")
		}
		// add user to both the participantArray and attach a pivot for them.
		chatgroup.participantArray.append(cacheUser.userID)
		try await chatgroup.save(on: req.db)
		let newParticipant = try ChatGroupParticipant(cacheUser.userID, chatgroup)
		newParticipant.readCount = 0
		let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
		newParticipant.hiddenCount = try await chatgroup.$chatGroupPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes)
			.count()
		try await newParticipant.save(on: req.db)
		try forwardMembershipChangeToSockets(chatgroup, participantID: cacheUser.userID, joined: true, on: req)
		let chatGroupData = try buildChatGroupData(from: chatgroup, with: newParticipant, for: cacheUser, on: req)
		// return with 201 status
		let response = Response(status: .created)
		try response.content.encode(chatGroupData)
		return response
	}

	/// `POST /api/v3/chatgroup/ID/unjoin`
	///
	/// Remove the current user from the ChatGroup. If the `.maxCapacity` of the chatgroup had
	/// previously been reached, the first user from the waiting list, if any, is moved to the
	/// participant list.
	///
	/// - Parameter chatGroupID: in the URL path.
	/// - Throws: 400 error if the supplied ID is not a chatgroup barrel. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` containing the updated chatgroup data.
	func unjoinHandler(_ req: Request) async throws -> ChatGroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard chatgroup.chatGroupType != .closed else {
			throw Abort(.badRequest, reason: "Cannot remove members to a closed chat")
		}
		// remove user from participantArray and also remove the pivot.
		if let index = chatgroup.participantArray.firstIndex(of: cacheUser.userID) {
			chatgroup.participantArray.remove(at: index)
		}
		try await chatgroup.save(on: req.db)
		try await chatgroup.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).delete()
		try await deleteChatGroupNotifications(userIDs: [cacheUser.userID], chatgroup: chatgroup, on: req)
		try forwardMembershipChangeToSockets(chatgroup, participantID: cacheUser.userID, joined: false, on: req)
		return try buildChatGroupData(from: chatgroup, with: nil, for: cacheUser, on: req)
	}

	// MARK: Posts

	/// `POST /api/v3/chatgroup/ID/post`
	///
	/// Add a `ChatGroupPost` to the specified `ChatGroup`.
	///
	/// Open chatgroup types are only permitted to have 1 image per post. Private chatgroups (aka Seamail) cannot have any images.
	///
	/// - Parameter chatGroupID: in URL path
	/// - Parameter requestBody: `PostContentData`
	/// - Throws: 404 error if the chatgroup is not available. A 5xx response should be reported
	///   as a likely bug, please and thank you.
	/// - Returns: `ChatGroupPostData` containing the user's new post.
	func postAddHandler(_ req: Request) async throws -> ChatGroupPostData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()
		// see PostContentData.validations()
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard ![.closed, .open].contains(chatgroup.chatGroupType) || data.images.count == 0 else {
			throw Abort(.badRequest, reason: "Private conversations can't contain photos.")
		}
		guard data.images.count <= 1 else {
			throw Abort(.badRequest, reason: "posts may only have one image")
		}
		guard chatgroup.participantArray.contains(cacheUser.userID) || cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "user is not member of \(chatgroup.chatGroupType.lfgLabel); cannot post")
		}
		guard !cacheUser.getBlocks().contains(chatgroup.$owner.id) else {
			throw Abort(.notFound, reason: "\(chatgroup.chatGroupType.lfgLabel) is not available")
		}
		guard chatgroup.moderationStatus != .locked else {
			// Note: Users should still be able to post in a quarantined LFG so they can figure out what (else) to do.
			throw Abort(.badRequest, reason: "\(chatgroup.chatGroupType.lfgLabel) is locked; cannot post.")
		}
		// process image
		let filenames = try await processImages(data.images, usage: .chatGroupPost, on: req)
		// create and save the new post, update chatgroups' cached post count
		let effectiveAuthor = data.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let filename = filenames.count > 0 ? filenames[0] : nil
		let post = try ChatGroupPost(chatgroup: chatgroup, authorID: effectiveAuthor.userID, text: data.text, image: filename)
		chatgroup.postCount += 1
		try await post.save(on: req.db)
		try await chatgroup.save(on: req.db)
		// If any participants block or mute this user, increase their hidden post count as they won't see this post.
		// The nice thing about doing it this way is most of the time there will be no blocks and nothing to do.
		var participantNotifyList: [UUID] = []
		for participantUserID in chatgroup.participantArray {
			guard let participantCacheUser = req.userCache.getUser(participantUserID) else {
				continue
			}
			if participantCacheUser.getBlocks().contains(effectiveAuthor.userID)
				|| participantCacheUser.getMutes().contains(effectiveAuthor.userID)
			{
				if let pivot = try await getUserPivot(chatgroup: chatgroup, userID: participantUserID, on: req.db) {
					pivot.hiddenCount += 1
					try await pivot.save(on: req.db)
				}
			}
			else if participantUserID != cacheUser.userID {
				participantNotifyList.append(participantUserID)
			}
		}
		try await post.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		var infoStr = "@\(effectiveAuthor.username) wrote, \"\(post.text)\""
		if chatgroup.chatGroupType != .closed {
			infoStr.append(" in \(chatgroup.chatGroupType.lfgLabel) \"\(chatgroup.title)\".")
		}
		try await addNotifications(users: participantNotifyList, type: chatgroup.notificationType(), info: infoStr, on: req)
		try forwardPostToSockets(chatgroup, post, on: req)
		// A user posting is assumed to have read all prev posts. (even if this proves untrue, we should increment
		// readCount as they've read the post they just wrote!)
		if let pivot = try await getUserPivot(chatgroup: chatgroup, userID: cacheUser.userID, on: req.db) {
			pivot.readCount = chatgroup.postCount - pivot.hiddenCount
			try await pivot.save(on: req.db)
		}
		return try ChatGroupPostData(post: post, author: effectiveAuthor.makeHeader())
	}

	/// `POST /api/v3/chatgroup/post/ID/delete`
	/// `DELETE /api/v3/chatgroup/post/ID`
	///
	/// Delete a `ChatGroupPost`. Must be author of post.
	///
	/// - Parameter chatGroupID: in URL path
	/// - Throws: 403 error if user is not the post author. 404 error if the chatgroup is not
	///   available. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: HTTP 204 No Content
	func postDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ChatGroupPost.findFromParameter(chatGroupPostIDParam, on: req)
		try cacheUser.guardCanModifyContent(post)
		// get chatgroup and all its participant pivots. Also get count of posts before the one we're deleting.
		guard let chatgroup = try await post.$chatGroup.query(on: req.db).with(\.$participants.$pivots).first() else {
			throw Abort(.internalServerError, reason: "On delete: container for post not found")
		}
		guard !cacheUser.getBlocks().contains(chatgroup.$owner.id) else {
			throw Abort(.notFound, reason: "\(chatgroup.chatGroupType.lfgLabel) is not available")
		}
		let postIndex = try await chatgroup.$chatGroupPosts.query(on: req.db).filter(\.$id < post.requireID()).count()
		// delete post, reduce post count cached in chatgroup
		chatgroup.postCount -= 1
		try await chatgroup.save(on: req.db)
		try await post.delete(on: req.db)
		var adjustNotificationCountForUsers: [UUID] = []
		for participantPivot in chatgroup.$participants.pivots {
			// If this user was hiding this post, reduce their hidden count as the post is gone.
			var pivotNeedsSave = false
			if let participantCacheUser = req.userCache.getUser(participantPivot.$user.id),
				participantCacheUser.getBlocks().contains(cacheUser.userID)
					|| participantCacheUser.getMutes().contains(cacheUser.userID)
			{
				participantPivot.hiddenCount = max(participantPivot.hiddenCount - 1, 0)
				pivotNeedsSave = true
			}
			// If the user has read the post being deleted, reduce their read count by 1.
			if participantPivot.readCount > postIndex {
				participantPivot.readCount -= 1
				pivotNeedsSave = true
			}
			if pivotNeedsSave {
				try await participantPivot.save(on: req.db)
			}
			else if participantPivot.$user.id != cacheUser.userID {
				adjustNotificationCountForUsers.append(participantPivot.$user.id)
			}
		}
		_ = try await subtractNotifications(
			users: adjustNotificationCountForUsers,
			type: chatgroup.notificationType(),
			on: req
		)
		try await post.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		return .noContent
	}

	/// `POST /api/v3/chatgroup/post/ID/report`
	///
	/// Creates a `Report` regarding the specified `ChatGroupPost`.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter postID: in URL path, the ID of the post being reported.
	/// - Parameter requestBody: `ReportData` payload in the HTTP body.
	/// - Throws: 400 error if the post is private.
	/// - Throws: 404 error if the parent chatgroup of the post could not be found.
	/// - Returns: 201 Created on success.
	func reportChatGroupPostHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedPost = try await ChatGroupPost.findFromParameter(chatGroupPostIDParam, on: req)
		guard let reportedchatgroup = try await ChatGroup.find(reportedPost.$chatGroup.id, on: req.db) else {
			throw Abort(.notFound, reason: "While trying to file report: could not find container for post")
		}
		guard reportedchatgroup.chatGroupType != ChatGroupType.closed else {
			throw Abort(.badRequest, reason: "cannot report private (closed) posts")
		}
		return try await reportedPost.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: ChatGroup Management

	/// `POST /api/v3/chatgroup/create`
	///
	/// Create a `ChatGroup`. The creating user is automatically added to the participant list.
	///
	/// The list of recognized values for use in the `.chatGroupType` field is obtained from
	/// `GET /api/v3/chatgroup/types`.
	///
	/// The `startTime`, `endTime`, and `location` fields are optional. Pass nil for these fields if the
	/// values are unknown/not applicable. Clients should convert nils in these fields to "TBD" for display.
	///
	/// - Important: Do **not** pass "0" as the date value. Unless you really are scheduling
	///   something for the first stroke of midnight in 1970.
	///
	/// A value of 0 in either the `.minCapacity` or `.maxCapacity` fields indicates an undefined
	/// limit: "there is no minimum", "there is no maximum".
	///
	/// - Parameter requestBody: `ChatGroupContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: 201 Created; `ChatGroupData` containing the newly created chatgroup.
	func createHandler(_ req: Request) async throws -> Response {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "User cannot create LFGs/Seamails.")
		// see `ChatGroupContentData.validations()`
		let data = try ValidatingJSONDecoder().decode(ChatGroupContentData.self, fromBodyOf: req)
		var creator = user
		if data.createdByTwitarrTeam == true {
			guard user.accessLevel >= .twitarrteam else {
				throw Abort(.badRequest, reason: "Must have TwitarrTeam access to post as @TwitarrTeam")
			}
			guard let ttUser = req.userCache.getUser(username: "TwitarrTeam") else {
				throw Abort(.internalServerError, reason: "Cannot find @TwitarrTeam user")
			}
			creator = ttUser
		}
		else if data.createdByModerator == true {
			guard user.accessLevel >= .moderator else {
				throw Abort(.badRequest, reason: "Must have moderator access to post as @moderator")
			}
			guard let modUser = req.userCache.getUser(username: "moderator") else {
				throw Abort(.internalServerError, reason: "Cannot find @moderator user")
			}
			creator = modUser
		}
		let chatgroup = ChatGroup(
			owner: creator.userID,
			chatGroupType: data.chatGroupType,
			title: data.title,
			info: data.info,
			location: data.location,
			startTime: data.startTime,
			endTime: data.endTime,
			minCapacity: data.minCapacity,
			maxCapacity: data.maxCapacity
		)
		// This filters out anyone on the creator's blocklist and any duplicate IDs.
		var creatorBlocks = creator.getBlocks()
		var initialUsers = ([creator.userID] + data.initialUsers).filter { creatorBlocks.insert($0).inserted }
		if creator.userID != user.userID {
			initialUsers = initialUsers.filter { $0 != user.userID }
		}
		guard data.chatGroupType != .closed || initialUsers.count >= 2 else {
			throw Abort(.badRequest, reason: "Fewer than 2 users in seamail after applying user filters")
		}
		guard initialUsers.count >= 1 else {
			throw Abort(.badRequest, reason: "Cannot create \(chatgroup.chatGroupType.lfgLabel) with 0 participants")
		}
		chatgroup.participantArray = initialUsers
		try await chatgroup.save(on: req.db)
		let participants = try await User.query(on: req.db).filter(\.$id ~~ initialUsers).all()
		try await chatgroup.$participants.attach(
			participants,
			on: req.db,
			{
				$0.readCount = 0
				$0.hiddenCount = 0
			}
		)
		let creatorPivot = try await chatgroup.$participants.$pivots.query(on: req.db).filter(\.$user.$id == creator.userID)
			.first()
		let chatGroupData = try buildChatGroupData(from: chatgroup, with: creatorPivot, posts: [], for: user, on: req)
		// with 201 status
		let response = Response(status: .created)
		try response.content.encode(chatGroupData)
		return response
	}

	/// `POST /api/v3/chatgroup/ID/cancel`
	///
	/// Cancel a ChatGroup. Owner only. Cancelling a ChatGroup is different from deleting it. A canceled chatgroup is still visible; members may still post to it.
	/// But, a cenceled chatgroup does not show up in searches for open chatgroups, and should be clearly marked in UI to indicate that it's been canceled.
	///
	/// - Note: Eventually, cancelling a chatgroup should notifiy all members via the notifications endpoint.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Throws: 403 error if user is not the chatgroup owner. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` with the updated chatgroup info.
	func cancelHandler(_ req: Request) async throws -> ChatGroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard chatgroup.$owner.id == cacheUser.userID else {
			throw Abort(.forbidden, reason: "user does not own this \(chatgroup.chatGroupType.lfgLabel)")
		}
		// FIXME: this should send out notifications
		chatgroup.cancelled = true
		try await chatgroup.save(on: req.db)
		let pivot = try await chatgroup.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.first()
		return try buildChatGroupData(from: chatgroup, with: pivot, for: cacheUser, on: req)
	}

	/// `POST /api/v3/chatgroup/ID/delete`
	/// `DELETE /api/v3/chatgroup/ID`
	///
	/// Delete the specified `ChatGroup`. This soft-deletes the chatgroup. Posts are left as-is.
	///
	/// To delete, the user must have an access level allowing them to delete the chatgroup. Currently this means moderators and above.
	/// The owner of a chatgroup may Cancel the chatgroup, which tells the members the chatgroup was cancelled, but does not delete it.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func chatGroupDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete an \(chatgroup.chatGroupType.lfgLabel).")
		}
		try cacheUser.guardCanModifyContent(chatgroup)
		try await deleteChatGroupNotifications(userIDs: chatgroup.participantArray, chatgroup: chatgroup, on: req)
		try await chatgroup.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await chatgroup.$participants.detachAll(on: req.db).get()
		try await chatgroup.delete(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/chatgroup/ID/update`
	///
	/// Update the specified ChatGroup with the supplied data. Updating a cancelled chatgroup will un-cancel it.
	///
	/// - Note: All fields in the supplied `ChatGroupContentData` must be filled, just as if the chatgroup
	///   were being created from scratch. If there is demand, using a set of more efficient
	///   endpoints instead of this single monolith can be considered.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Parameter requestBody: `ChatGroupContentData` payload in the HTTP body.
	/// - Throws: 400 error if the data is not valid. 403 error if user is not chatgroup owner.
	///   A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` containing the updated chatgroup info.
	func updateHandler(_ req: Request) async throws -> ChatGroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// see ChatGroupContentData.validations()
		let data = try ValidatingJSONDecoder().decode(ChatGroupContentData.self, fromBodyOf: req)
		// get chatgroup
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		try cacheUser.guardCanModifyContent(chatgroup, customErrorString: "User cannot modify LFG")
		guard ![.closed, .open].contains(chatgroup.chatGroupType) else {
			throw Abort(.forbidden, reason: "Cannot edit info on Seamail chats")
		}
		guard ![.closed, .open].contains(data.chatGroupType) else {
			throw Abort(.forbidden, reason: "Cannot turn a LFG into a Seamail chat")
		}
		if data.title != chatgroup.title || data.location != chatgroup.location || data.info != chatgroup.info {
			let chatGroupEdit = try chatgroupEdit(chatgroup: chatgroup, editorID: cacheUser.userID)
			try await chatgroup.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
			try await chatGroupEdit.save(on: req.db)
		}
		chatgroup.chatGroupType = data.chatGroupType
		chatgroup.title = data.title
		chatgroup.info = data.info
		chatgroup.startTime = data.startTime
		chatgroup.endTime = data.endTime
		chatgroup.location = data.location
		chatgroup.minCapacity = data.minCapacity
		chatgroup.maxCapacity = data.maxCapacity
		chatgroup.cancelled = false
		try await chatgroup.save(on: req.db)
		let pivot = try await getUserPivot(chatgroup: chatgroup, userID: cacheUser.userID, on: req.db)
		return try buildChatGroupData(from: chatgroup, with: pivot, for: cacheUser, on: req)
	}

	/// `POST /api/v3/chatgroup/ID/user/ID/add`
	///
	/// Add the specified `User` to the specified LFG or open chat. This lets the owner invite others.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is already in barrel. 403 error if requester is not chatgroup
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` containing the updated chatgroup info.
	func userAddHandler(_ req: Request) async throws -> ChatGroupData {
		let requester = try req.auth.require(UserCacheData.self)
		// get chatgroup and user to add
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard chatgroup.chatGroupType != .closed else {
			throw Abort(.forbidden, reason: "Cannot add users to closed chat")
		}
		guard let userID = req.parameters.get(userIDParam.paramString, as: UUID.self),
			let cacheUser = req.userCache.getUser(userID)
		else {
			throw Abort(.forbidden, reason: "invalid user ID in request parameter")
		}
		guard chatgroup.$owner.id == requester.userID else {
			throw Abort(.forbidden, reason: "requester does not own \(chatgroup.chatGroupType.lfgLabel)")
		}
		guard !chatgroup.participantArray.contains(userID) else {
			throw Abort(.badRequest, reason: "user is already in \(chatgroup.chatGroupType.lfgLabel)")
		}
		guard !requester.getBlocks().contains(userID) else {
			throw Abort(.badRequest, reason: "user is not available")
		}
		chatgroup.participantArray.append(userID)
		let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
		let hiddenPostCount = try await chatgroup.$chatGroupPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count()
		try await chatgroup.save(on: req.db)
		let newParticipant = try ChatGroupParticipant(userID, chatgroup)
		newParticipant.readCount = 0
		newParticipant.hiddenCount = hiddenPostCount
		try await newParticipant.save(on: req.db)
		try forwardMembershipChangeToSockets(chatgroup, participantID: userID, joined: true, on: req)
		let effectiveUser = getEffectiveUser(user: requester, req: req, chatgroup: chatgroup)
		let pivot = try await chatgroup.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.first()
		return try buildChatGroupData(from: chatgroup, with: pivot, for: requester, on: req)
	}

	/// `POST /api/v3/chatgroup/ID/user/:userID/remove`
	///
	/// Remove the specified `User` from the specified ChatGroup barrel. This lets a chatgroup owner remove others.
	///
	/// - Parameter chatGroupID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is not in the barrel. 403 error if requester is not chatgroup
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ChatGroupData` containing the updated chatgroup info.
	func userRemoveHandler(_ req: Request) async throws -> ChatGroupData {
		let requester = try req.auth.require(UserCacheData.self)
		// get chatgroup and user to remove
		let removeUser = try await User.findFromParameter(userIDParam, on: req)
		let removeUserID = try removeUser.requireID()
		let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard chatgroup.chatGroupType != .closed else {
			throw Abort(.forbidden, reason: "Cannot remove users from closed chat")
		}
		guard chatgroup.$owner.id == requester.userID else {
			throw Abort(.forbidden, reason: "requester does not own \(chatgroup.chatGroupType.lfgLabel)")
		}
		// remove user
		guard let index = chatgroup.participantArray.firstIndex(of: removeUserID) else {
			throw Abort(.badRequest, reason: "user is not a member of this \(chatgroup.chatGroupType.lfgLabel)")
		}
		chatgroup.participantArray.remove(at: index)
		try await chatgroup.save(on: req.db)
		try await chatgroup.$participants.detach(removeUser, on: req.db)
		try await deleteChatGroupNotifications(userIDs: [removeUserID], chatgroup: chatgroup, on: req)
		try forwardMembershipChangeToSockets(chatgroup, participantID: removeUserID, joined: false, on: req)
		let effectiveUser = getEffectiveUser(user: requester, req: req, chatgroup: chatgroup)
		let pivot = try await chatgroup.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.first()
		return try buildChatGroupData(from: chatgroup, with: pivot, for: requester, on: req)
	}

	/// `POST /api/v3/chatgroup/ID/report`
	///
	/// Creates a `Report` regarding the specified `ChatGroup`. This reports on the ChatGroup itself, not any of its posts in particular. This could mean a
	/// ChatGroup with reportable content in its Title, Info, or Location fields, or a bunch of reportable posts in the chatgroup.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter chatGroupID: in URL path, the ChatGroup ID to report.
	/// - Parameter requestBody: `ReportData`
	/// - Returns: 201 Created on success.
	func reportChatGroupHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedChatGroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
		guard reportedChatGroup.chatGroupType != .closed else {
			throw Abort(.forbidden, reason: "Cannot file reports on closed chats")
		}
		return try await reportedChatGroup.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: - Socket Functions

	/// `WS /api/v3/chatgroup/:chatGroupID/socket`
	///
	/// Opens a websocket to receive updates on the given chatgroup. At the moment there's only 2 messages that the client may receive:
	/// - `SocketChatGroupPostData` - sent when a post is added to the chatgroup.
	/// - `SocketMemberChangeData` - sent when a member joins/leaves the chatgroup.
	///
	/// Note that there's a bunch of other state change that can happen with a chatgroup; I haven't built out code to send socket updates for them.
	/// The socket returned by this call is only intended for receiving updates; there are no client-initiated messages defined for this socket.
	/// Posting messages, leaving the chatgroup, updating or canceling the chatgroup and any other state changes should be performed using the various
	/// POST methods of this controller.
	///
	/// The server validates membership before sending out each socket message, but be sure to close the socket if the user leaves the chatgroup.
	/// This method is designed to provide updates only while a user is viewing the chatgroup in your app--don't open one of these sockets for each
	/// chatgroup a user joins and keep them open continually. Use `WS /api/v3/notification/socket` for long-term status updates.
	func createGroupChatSocket(_ req: Request, _ ws: WebSocket) async {
		do {
			let user = try req.auth.require(UserCacheData.self)
			let chatgroup = try await ChatGroup.findFromParameter(chatGroupIDParam, on: req)
			guard userCanViewMemberData(user: user, chatgroup: chatgroup), let chatGroupID = try? chatgroup.requireID() else {
				throw Abort(.badRequest, reason: "User can't vew messages in this LFG")
			}
			let userSocket = UserSocket(userID: user.userID, socket: ws, chatGroupID: chatGroupID, htmlOutput: false)
			try req.webSocketStore.storeChatGroupSocket(userSocket)

			ws.onClose.whenComplete { result in
				try? req.webSocketStore.removeChatGroupSocket(userSocket)
			}
		}
		catch {
			try? await ws.close()
		}
	}

	// Checks for sockets open on this chatgroup, and sends the post to each of them.
	func forwardPostToSockets(_ chatgroup: ChatGroup, _ post: ChatGroupPost, on req: Request) throws {
		try req.webSocketStore.getChatGroupSockets(chatgroup.requireID())
			.forEach { userSocket in
				let postAuthor = try req.userCache.getHeader(post.$author.id)
				guard let socketOwner = req.userCache.getUser(userSocket.userID),
					userCanViewMemberData(user: socketOwner, chatgroup: chatgroup),
					!(socketOwner.getBlocks().contains(postAuthor.userID)
						|| socketOwner.getMutes().contains(postAuthor.userID))
				else {
					return
				}
				var leafPost = try SocketChatGroupPostData(post: post, author: postAuthor)
				if userSocket.htmlOutput {
					struct ChatGroupPostContext: Encodable {
						var userID: UUID
						var chatGroupPost: SocketChatGroupPostData
						var showModButton: Bool
					}
					let ctx = ChatGroupPostContext(
						userID: userSocket.userID,
						chatGroupPost: leafPost,
						showModButton: socketOwner.accessLevel.hasAccess(.moderator) && chatgroup.chatGroupType != .closed
					)
					_ = req.view.render("ChatGroup/chatGroupPost", ctx)
						.flatMapThrowing { postBuffer in
							if let data = postBuffer.data.getData(at: 0, length: postBuffer.data.readableBytes),
								let htmlString = String(data: data, encoding: .utf8)
							{
								leafPost.html = htmlString
								let data = try JSONEncoder().encode(leafPost)
								if let dataString = String(data: data, encoding: .utf8) {
									userSocket.socket.send(dataString)
								}
							}
						}
				}
				else {
					let data = try JSONEncoder().encode(leafPost)
					if let dataString = String(data: data, encoding: .utf8) {
						userSocket.socket.send(dataString)
					}
				}
			}
	}

	// Checks for sockets open on this chatgroup, and sends the membership change info to each of them.
	func forwardMembershipChangeToSockets(_ chatgroup: ChatGroup, participantID: UUID, joined: Bool, on req: Request) throws
	{
		try req.webSocketStore.getChatGroupSockets(chatgroup.requireID())
			.forEach { userSocket in
				let participantHeader = try req.userCache.getHeader(participantID)
				guard let socketOwner = req.userCache.getUser(userSocket.userID),
					userCanViewMemberData(user: socketOwner, chatgroup: chatgroup),
					!socketOwner.getBlocks().contains(participantHeader.userID)
				else {
					return
				}
				var change = SocketChatGroupMemberChangeData(user: participantHeader, joined: joined)
				if userSocket.htmlOutput {
					change.html = "<i>\(participantHeader.username) has \(joined ? "entered" : "left") the chat</i>"
				}
				let data = try JSONEncoder().encode(change)
				if let dataString = String(data: data, encoding: .utf8) {
					userSocket.socket.send(dataString)
				}
			}
	}
}

// MARK: - Helper Functions

extension ChatGroupController {

	// MembersOnlyData is only filled in if:
	//	* The user is a member of the chatgroup (pivot is not nil) OR
	//  * The user is a moderator and the chatgroup is not private
	//
	// Pivot should always be nil if the current user is not a member of the chatgroup.
	// To read the 'moderator' or 'twitarrteam' seamail, verify the requestor has access and call this fn with
	// the effective user's account.
	func buildChatGroupData(
		from chatgroup: ChatGroup,
		with pivot: ChatGroupParticipant? = nil,
		posts: [ChatGroupPostData]? = nil,
		for cacheUser: UserCacheData,
		on req: Request
	) throws -> ChatGroupData {
		let userBlocks = cacheUser.getBlocks()
		// init return struct
		let ownerHeader = try req.userCache.getHeader(chatgroup.$owner.id)
		var chatGroupData: ChatGroupData = try ChatGroupData(chatgroup: chatgroup, owner: ownerHeader)
		if pivot != nil || (cacheUser.accessLevel.hasAccess(.moderator) && chatgroup.chatGroupType != .closed) {
			let allParticipantHeaders = req.userCache.getHeaders(chatgroup.participantArray)

			// masquerade blocked users
			let valids = allParticipantHeaders.map { (member: UserHeader) -> UserHeader in
				if userBlocks.contains(member.userID) {
					return UserHeader.Blocked
				}
				return member
			}
			// populate chatGroupData's participant list and waiting list
			var participants: [UserHeader]
			var waitingList: [UserHeader]
			if valids.count > chatgroup.maxCapacity && chatgroup.maxCapacity > 0 {
				participants = Array(valids[valids.startIndex..<chatgroup.maxCapacity])
				waitingList = Array(valids[chatgroup.maxCapacity..<valids.endIndex])
			}
			else {
				participants = valids
				waitingList = []
			}
			chatGroupData.members = ChatGroupData.MembersOnlyData(
				participants: participants,
				waitingList: waitingList,
				postCount: chatgroup.postCount - (pivot?.hiddenCount ?? 0),
				readCount: pivot?.readCount ?? 0,
				posts: posts
			)
		}
		return chatGroupData
	}

	// Remember that there can be posts by authors who are not currently participants.
	func buildPostsForChatGroup(_ chatgroup: ChatGroup, pivot: ChatGroupParticipant?, on req: Request, user: UserCacheData) async throws
		-> ([ChatGroupPostData], Paginator)
	{
		let readCount = pivot?.readCount ?? 0
		let hiddenCount = pivot?.hiddenCount ?? 0
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let start = (req.query[Int.self, at: "start"] ?? ((readCount - 1) / limit) * limit)
			.clamped(to: 0...chatgroup.postCount)
		// get posts
		let posts = try await ChatGroupPost.query(on: req.db)
			.filter(\.$chatGroup.$id == chatgroup.requireID())
			.filter(\.$author.$id !~ user.getBlocks())
			.filter(\.$author.$id !~ user.getMutes())
			.sort(\.$createdAt, .ascending)
			.range(start..<(start + limit))
			.all()
		let postDatas = try posts.map { try ChatGroupPostData(post: $0, author: req.userCache.getHeader($0.$author.id)) }
		let paginator = Paginator(total: chatgroup.postCount - hiddenCount, start: start, limit: limit)

		// If this batch of posts is farther into the thread than the user has previously read, increase
		// the user's read count.
		if let pivot = pivot, start + limit > pivot.readCount {
			pivot.readCount = min(start + limit, chatgroup.postCount - pivot.hiddenCount)
			try await pivot.save(on: req.db)
			// If the user has now read all the posts (except those hidden from them) mark this notification as viewed.
			if pivot.readCount + pivot.hiddenCount >= chatgroup.postCount {
				try await markNotificationViewed(user: user, type: chatgroup.notificationType(), on: req)
			}
		}
		return (postDatas, paginator)
	}

	func getUserPivot(chatgroup: ChatGroup, userID: UUID, on db: Database) async throws -> ChatGroupParticipant? {
		return try await chatgroup.$participants.$pivots.query(on: db).filter(\.$user.$id == userID).first()
	}

	func userCanViewMemberData(user: UserCacheData, chatgroup: ChatGroup) -> Bool {
		return user.accessLevel.hasAccess(.moderator) || chatgroup.participantArray.contains(user.userID)
	}

	// For both Moderator and TwittarTeam access levels, there's a special user account with the same name.
	// Seamail to @moderator and @TwitarrTeam may be read by any user with the respective access levels.
	// Instead of designing a new entity for these group inboxes, they're just users that can't log in.
	func getEffectiveUser(user: UserCacheData, req: Request) throws -> UserCacheData {
		guard let effectiveUserParam = req.query[String.self, at: "foruser"] else {
			return user
		}
		var effectiveUser = user
		if effectiveUserParam == "moderator", let modUser = req.userCache.getUser(username: "moderator") {
			guard user.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "Only moderators can access moderator seamail.")
			}
			effectiveUser = modUser
		}
		if effectiveUserParam == "twitarrteam", let ttUser = req.userCache.getUser(username: "TwitarrTeam") {
			guard user.accessLevel.hasAccess(.twitarrteam) else {
				throw Abort(.forbidden, reason: "Only TwitarrTeam members can access TwitarrTeam seamail.")
			}
			effectiveUser = ttUser
		}
		return effectiveUser
	}

	// This version of getEffectiveUser checks the user against the chatgroup's membership, and also checks whether
	// user 'moderator' or user 'TwitarrTeam' is a member of the chatgroup and the user has the appropriate access level.
	//
	func getEffectiveUser(user: UserCacheData, req: Request, chatgroup: ChatGroup) -> UserCacheData {
		if chatgroup.participantArray.contains(user.userID) {
			return user
		}
		// If either of these 'special' users are chatgroup members and the user has high enough access, we can see the
		// members-only values of the chatgroup as the 'special' user.
		if user.accessLevel >= .twitarrteam, let ttUser = req.userCache.getUser(username: "TwitarrTeam"),
			chatgroup.participantArray.contains(ttUser.userID)
		{
			return ttUser
		}
		if user.accessLevel >= .moderator, let modUser = req.userCache.getUser(username: "moderator"),
			chatgroup.participantArray.contains(modUser.userID)
		{
			return modUser
		}
		// User isn't a member of the chatgroup, but they're still the effective user in this case.
		return user
	}
}
