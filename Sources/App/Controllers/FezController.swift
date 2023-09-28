import Crypto
import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/group/*` route endpoints and handler functions related to Looking For Group and Seamail chats.
struct GroupController: APIRouteCollection {

	// A struct with common URL query parameters for routes in the Group Controller.
	// Most route handlers don't actually use all these options; each handler's header comment
	// specifies what URL options it uses.
	// The decode() call decodes the URL Query into this struct; trying to decode keys the the handler doesn't use
	// doesn't matter; whether or not the URL Query contains the option or not. However, it is possible a malformed
	// but unused query parameter would result in an error for the call.
	struct GroupURLQueryStruct: Content {
		var type: [String]
		var excludetype: [String]
		var onlynew: Bool?
		var start: Int?
		var limit: Int?
		var cruiseDay: Int?
		var search: String?
		var hidePast: Bool?

		func getTypes() throws -> [GroupType]? {
			let includeTypes = try type.map { try GroupType.fromAPIString($0) }
			return includeTypes.count > 0 ? includeTypes : nil
		}

		func getExcludeTypes() throws -> [GroupType]? {
			let excludeTypes = try excludetype.map { try GroupType.fromAPIString($0) }
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

		// convenience route group for all /api/v3/group endpoints
		let groupRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .friendlygroup)).grouped("api", "v3", "group")

		// Open access routes
		groupRoutes.get("types", use: typesHandler)

		// endpoints available only when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: groupRoutes)
		tokenCacheAuthGroup.get("open", use: openHandler)
		tokenCacheAuthGroup.get("joined", use: joinedHandler)
		tokenCacheAuthGroup.get("owner", use: ownerHandler)
		tokenCacheAuthGroup.get(groupIDParam, use: groupHandler)
		tokenCacheAuthGroup.post("create", use: createHandler)
		tokenCacheAuthGroup.on(.POST, groupIDParam, "post", body: .collect(maxSize: "30mb"), use: postAddHandler)
		tokenCacheAuthGroup.webSocket(groupIDParam, "socket", onUpgrade: createGroupSocket)
		tokenCacheAuthGroup.post(groupIDParam, "cancel", use: cancelHandler)
		tokenCacheAuthGroup.post(groupIDParam, "join", use: joinHandler)
		tokenCacheAuthGroup.post(groupIDParam, "unjoin", use: unjoinHandler)
		tokenCacheAuthGroup.post("post", groupPostIDParam, "delete", use: postDeleteHandler)
		tokenCacheAuthGroup.delete("post", groupPostIDParam, use: postDeleteHandler)
		tokenCacheAuthGroup.post(groupIDParam, "user", userIDParam, "add", use: userAddHandler)
		tokenCacheAuthGroup.post(groupIDParam, "user", userIDParam, "remove", use: userRemoveHandler)
		tokenCacheAuthGroup.post(groupIDParam, "update", use: updateHandler)
		tokenCacheAuthGroup.post(groupIDParam, "delete", use: groupDeleteHandler)
		tokenCacheAuthGroup.delete(groupIDParam, use: groupDeleteHandler)
		tokenCacheAuthGroup.post(groupIDParam, "report", use: reportGroupHandler)
		tokenCacheAuthGroup.post("post", groupPostIDParam, "report", use: reportGroupPostHandler)

	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

	// MARK: Retrieving Groups

	/// `/GET /api/v3/group/types`
	///
	/// Retrieve a list of all values for `GroupType` as strings.
	///
	/// - Returns: An array of `String` containing the `.label` value for each type.
	func typesHandler(_ req: Request) throws -> [String] {
		return GroupType.allCases.map { $0.label }
	}

	/// `GET /api/v3/group/open`
	///
	/// Retrieve FriendlyGroups with open slots and a startTime of no earlier than one hour ago. Results are returned sorted by start time, then by title.
	///
	/// **URL Query Parameters:**
	///
	/// * `?cruiseday=INT` - Only return groups occuring on this day of the cruise. Embarkation Day is day 0.
	/// * `?type=STRING` - Only return groups of this type, there STRING is a `GroupType.fromAPIString()` string.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of groups to return; defaults to 50.
	/// - `?hidepast=BOOLEAN` - Show groups that started more than one hour in the past. For this endpoint, this defaults to TRUE.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `GroupData` containing current groups with open slots.
	func openHandler(_ req: Request) async throws -> GroupListData {
		let urlQuery = try req.query.decode(GroupURLQueryStruct.self)
		let cacheUser = try req.auth.require(UserCacheData.self)

		let groupQuery = FriendlyGroup.query(on: req.db)
			.filter(\.$groupType !~ [.closed, .open])
			.filter(\.$owner.$id !~ cacheUser.getBlocks())
			.filter(\.$cancelled == false)

		if urlQuery.hidePast ?? true {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			groupQuery.filter(\.$startTime > searchStartTime)
		}

		if let typeFilter = try urlQuery.getTypes() {
			groupQuery.filter(\.$groupType ~~ typeFilter)
		}
		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			let threeAMCutoff =
				portCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate())
				?? Settings.shared.cruiseStartDate()
			let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: threeAMCutoff) ?? threeAMCutoff
			let dayEnd = portCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
			groupQuery.filter(\.$startTime >= dayStart).filter(\.$startTime < dayEnd)
		}
		let groupCount = try await groupQuery.count()
		let groups = try await groupQuery.sort(\.$startTime, .ascending).sort(\.$title, .ascending)
			.range(urlQuery.calcRange()).all()
		let groupDataArray: [GroupData] = try groups.compactMap { group in
			// Groups are only 'open' if their waitlist is < 1/2 the size of their capacity. A group with a max of 10 people
			// could have a waitlist of 5, then it stops showing up in 'open' searches.
			if (group.maxCapacity == 0 || group.participantArray.count < Int(Double(group.maxCapacity) * 1.5))
				&& !group.participantArray.contains(cacheUser.userID)
			{
				return try buildGroupData(from: group, with: nil, for: cacheUser, on: req)
			}
			return nil
		}
		return GroupListData(
			paginator: Paginator(total: groupCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()),
			groups: groupDataArray
		)
	}

	/// `GET /api/v3/group/joined`
	///
	/// Retrieve all the FriendlyGroup chats that the user has joined. Results are sorted by descending group update time.
	///
	/// **Query Parameters:**
	/// * `?cruiseday=INT` - Only return groups occuring on this day of the cruise. Embarkation Day is day 0.
	/// - `?type=STRING` - Only return groups of the given groupType. See `GroupType` for a list.
	/// - `?excludetype=STRING` - Don't return groups of the given type. See `GroupType` for a list.
	/// - `?onlynew=TRUE` - Only return groups with unread messages.
	/// - `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// - `?limit=INT` - The maximum number of groups to return; defaults to 50.
	/// - `?search=STRING` - Only show groups whose title, info, or any post contains the given string.
	/// - `?hidepast=BOOLEAN` - Hide groups that started more than one hour in the past. For this endpoint, this defaults to FALSE.
	///
	/// Moderators and above can use the `foruser` query parameter to access pseudo-accounts:
	///
	/// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	///
	/// `/GET /api/v3/group/types` is  the canonical way to get the list of acceptable values. Type and excludetype are exclusive options, obv.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `GroupData` containing all the groups joined by the user.
	func joinedHandler(_ req: Request) async throws -> GroupListData {
		let urlQuery = try req.query.decode(GroupURLQueryStruct.self)
		let cacheUser = try req.auth.require(UserCacheData.self)
		let effectiveUser = try getEffectiveUser(user: cacheUser, req: req)
		let query = GroupParticipant.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.join(FriendlyGroup.self, on: \GroupParticipant.$group.$id == \FriendlyGroup.$id)
		if let includeTypes = try urlQuery.getTypes() {
			query.filter(FriendlyGroup.self, \.$groupType ~~ includeTypes)
		}
		else if let excludeTypes = try urlQuery.getExcludeTypes() {
			query.filter(FriendlyGroup.self, \.$groupType !~ excludeTypes)
		}

		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			let threeAMCutoff =
				portCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate())
				?? Settings.shared.cruiseStartDate()
			let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: threeAMCutoff) ?? threeAMCutoff
			let dayEnd = portCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
			query.filter(FriendlyGroup.self, \.$startTime >= dayStart).filter(FriendlyGroup.self, \.$startTime < dayEnd)
		}

		if urlQuery.hidePast ?? false {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			query.filter(FriendlyGroup.self, \.$startTime > searchStartTime)
		}

		if let onlyNew = urlQuery.onlynew {
			// Uses a custom filter to test "readCount + hiddenCount < FriendlyGroup.postCount". If true, there's unread messages
			// in this chat. Because it uses a custom filter for parameter 1, the other params use the weird long-form notation.
			query.filter(
				DatabaseQuery.Field.custom("\(GroupParticipant().$readCount.key) + \(GroupParticipant().$hiddenCount.key)"),
				onlyNew ? DatabaseQuery.Filter.Method.lessThan : DatabaseQuery.Filter.Method.equal,
				DatabaseQuery.Field.path(FriendlyGroup.path(for: \.$postCount), schema: FriendlyGroup.schema)
			)
		}
		if var searchStr = urlQuery.search {
			searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			query.join(GroupPost.self, on: \GroupPost.$group.$id == \FriendlyGroup.$id, method: .left)
			query.group(.or) { group in
				group.fullTextFilter(GroupPost.self, \.$text, searchStr)
					.fullTextFilter(FriendlyGroup.self, \.$title, searchStr)
					.fullTextFilter(FriendlyGroup.self, \.$info, searchStr)
			}
			// We joined GroupPost above, but we need to exclude its fields from the result set to prevent duplicates
			query.fields(for: GroupParticipant.self).fields(for: FriendlyGroup.self).unique()
		}
		async let groupCount = try query.count()
		async let pivots = query.sort(FriendlyGroup.self, \.$updatedAt, .descending).range(urlQuery.calcRange()).all()
		let groupDataArray = try await pivots.map { pivot -> GroupData in
			let group = try pivot.joined(FriendlyGroup.self)
			return try buildGroupData(from: group, with: pivot, for: effectiveUser, on: req)
		}
		return try await GroupListData(
			paginator: Paginator(total: groupCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()),
			groups: groupDataArray
		)
	}

	/// `GET /api/v3/group/owner`
	///
	/// Retrieve the FriendlyGroup chats created by the user.
	///
	/// - Note: There is no block filtering on this endpoint. In theory, a block could only
	///   apply if it were set *after* the group had been joined by the second party. The
	///   owner of the group has the ability to remove users if desired, and the group itself is no
	///   longer visible to the non-owning party.
	///
	/// **Query Parameters:**
	/// * `?cruiseday=INT` - Only return groups occuring on this day of the cruise. Embarkation Day is day 0.
	/// - `?type=STRING` - Only return groups of the given groupType. See `GroupType` for a list.
	/// - `?excludetype=STRING` - Don't return groups of the given type. See `GroupType` for a list.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of groups to return; defaults to 50.
	/// - `?hidepast=BOOLEAN` - Hide groups that started more than one hour in the past. For this endpoint, this defaults to FALSE.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `GroupData` containing all the groups created by the user.
	func ownerHandler(_ req: Request) async throws -> GroupListData {
		let urlQuery = try req.query.decode(GroupURLQueryStruct.self)
		let user = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = FriendlyGroup.query(on: req.db).filter(\.$owner.$id == user.userID)
			.join(GroupParticipant.self, on: \GroupParticipant.$group.$id == \FriendlyGroup.$id)
			.filter(GroupParticipant.self, \.$user.$id == user.userID)
		if let includeTypes = try urlQuery.getTypes() {
			query.filter(\.$groupType ~~ includeTypes)
		}
		else if let excludeTypes = try urlQuery.getExcludeTypes() {
			query.filter(\.$groupType !~ excludeTypes)
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

		// get owned groups
		async let groupCount = query.count()
		async let groups = query.range(start..<(start + limit)).sort(\.$createdAt, .descending).all()
		// convert to GroupData
		let groupDataArray = try await groups.map { (group) -> GroupData in
			let userParticipant = try group.joined(GroupParticipant.self)
			return try buildGroupData(from: group, with: userParticipant, for: user, on: req)
		}
		return try await GroupListData(
			paginator: Paginator(total: groupCount, start: start, limit: limit),
			groups: groupDataArray
		)
	}

	/// `GET /api/v3/group/:group_ID`
	///
	/// Retrieve information about the specified FriendlyGroup. For users that aren't members of the group, this info will be the same as
	/// the info returned for `GET /api/v3/group/open`. For users that have joined the group the `GroupData.MembersOnlyData` will be populated, as will
	/// the `GroupPost`s.
	///
	/// **Query Parameters:**
	/// * `?start=INT` - The offset to the first post to return in the array of posts.
	/// * `?limit=INT` - The maximum number of posts to return; defaults to 50.
	///
	/// Start and limit only have an effect when the user is a member of the Group. Limit defaults to 50 and start defaults to `(readCount / limit) * limit`,
	/// where readCount is how many posts the user has read already.
	///
	/// Moderators and above can use the `foruser` query parameter to access pseudo-accounts:
	///
	/// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	///
	/// When a member calls this method, it updates the member's `readCount`, marking all posts read up to `start + limit`.
	/// However, the returned readCount is the value before updating. If there's 5 posts in the chat, and the member has read 3 of them, the returned
	/// `GroupData` has 5 posts, we return 3 in `GroupData.readCount`field, and update the pivot's readCount to 5.
	///
	/// `GroupPost`s are ordered by creation time.
	///
	/// - Note: Posts are subject to block and mute user filtering, but mutewords are ignored
	///   in order to not suppress potentially important information.
	///
	/// - Parameter groupID: in the URL path.
	/// - Throws: 404 error if a block between the user and group owner applies. A 5xx response
	///   should be reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` with group info and all discussion posts.
	func groupHandler(_ req: Request) async throws -> GroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		let effectiveUser = getEffectiveUser(user: cacheUser, req: req, group: group)
		guard !cacheUser.getBlocks().contains(group.$owner.id) else {
			throw Abort(.notFound, reason: "this \(group.groupType.lfgLabel) is not available")
		}
		let pivot = try await group.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.first()
		var groupData = try buildGroupData(from: group, with: pivot, for: cacheUser, on: req)
		if let _ = groupData.members {
			let (posts, paginator) = try await buildPostsForGroup(group, pivot: pivot, on: req, user: cacheUser)
			groupData.members?.paginator = paginator
			groupData.members?.posts = posts
		}
		return groupData
	}

	// MARK: Membership

	/// `POST /api/v3/group/ID/join`
	///
	/// Add the current user to the FriendlyGroup. If the `.maxCapacity` of the group has been
	/// reached, the user is added to the waiting list.
	///
	/// - Note: A user cannot join a group that is owned by a blocked or blocking user. If any
	///   current participating or waitList user is in the user's blocks, their identity is
	///   replaced by a placeholder in the returned data. It is the user's responsibility to
	///   examine the participant list for conflicts prior to joining or attending.
	///
	/// - Parameter groupID: in the URL path.
	/// - Throws: 400 error if the supplied ID is not a group barrel or user is already in group.
	///   404 error if a block between the user and group owner applies. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` containing the updated group data.
	func joinHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard group.groupType != .closed else {
			throw Abort(.badRequest, reason: "Cannot add members to a closed chat")
		}
		guard group.groupType != .open else {
			throw Abort(.badRequest, reason: "Cannot add youself to a Seamail chat. Ask the chat creator to add you.")
		}
		guard !group.participantArray.contains(cacheUser.userID) else {
			throw Abort(.notFound, reason: "user is already a member of this \(group.groupType.lfgLabel)")
		}
		// respect blocks
		guard !cacheUser.getBlocks().contains(group.$owner.id) else {
			throw Abort(.notFound, reason: "This \(group.groupType.lfgLabel) is not available")
		}
		// add user to both the participantArray and attach a pivot for them.
		group.participantArray.append(cacheUser.userID)
		try await group.save(on: req.db)
		let newParticipant = try GroupParticipant(cacheUser.userID, group)
		newParticipant.readCount = 0
		let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
		newParticipant.hiddenCount = try await group.$groupPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes)
			.count()
		try await newParticipant.save(on: req.db)
		try forwardMembershipChangeToSockets(group, participantID: cacheUser.userID, joined: true, on: req)
		let groupData = try buildGroupData(from: group, with: newParticipant, for: cacheUser, on: req)
		// return with 201 status
		let response = Response(status: .created)
		try response.content.encode(groupData)
		return response
	}

	/// `POST /api/v3/group/ID/unjoin`
	///
	/// Remove the current user from the FriendlyGroup. If the `.maxCapacity` of the group had
	/// previously been reached, the first user from the waiting list, if any, is moved to the
	/// participant list.
	///
	/// - Parameter groupID: in the URL path.
	/// - Throws: 400 error if the supplied ID is not a group barrel. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` containing the updated group data.
	func unjoinHandler(_ req: Request) async throws -> GroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard group.groupType != .closed else {
			throw Abort(.badRequest, reason: "Cannot remove members to a closed chat")
		}
		// remove user from participantArray and also remove the pivot.
		if let index = group.participantArray.firstIndex(of: cacheUser.userID) {
			group.participantArray.remove(at: index)
		}
		try await group.save(on: req.db)
		try await group.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).delete()
		try await deleteGroupNotifications(userIDs: [cacheUser.userID], group: group, on: req)
		try forwardMembershipChangeToSockets(group, participantID: cacheUser.userID, joined: false, on: req)
		return try buildGroupData(from: group, with: nil, for: cacheUser, on: req)
	}

	// MARK: Posts

	/// `POST /api/v3/group/ID/post`
	///
	/// Add a `GroupPost` to the specified `FriendlyGroup`.
	///
	/// Open group types are only permitted to have 1 image per post. Private groups (aka Seamail) cannot have any images.
	///
	/// - Parameter groupID: in URL path
	/// - Parameter requestBody: `PostContentData`
	/// - Throws: 404 error if the group is not available. A 5xx response should be reported
	///   as a likely bug, please and thank you.
	/// - Returns: `GroupPostData` containing the user's new post.
	func postAddHandler(_ req: Request) async throws -> GroupPostData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()
		// see PostContentData.validations()
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard ![.closed, .open].contains(group.groupType) || data.images.count == 0 else {
			throw Abort(.badRequest, reason: "Private conversations can't contain photos.")
		}
		guard data.images.count <= 1 else {
			throw Abort(.badRequest, reason: "posts may only have one image")
		}
		guard group.participantArray.contains(cacheUser.userID) || cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "user is not member of \(group.groupType.lfgLabel); cannot post")
		}
		guard !cacheUser.getBlocks().contains(group.$owner.id) else {
			throw Abort(.notFound, reason: "\(group.groupType.lfgLabel) is not available")
		}
		guard group.moderationStatus != .locked else {
			// Note: Users should still be able to post in a quarantined LFG so they can figure out what (else) to do.
			throw Abort(.badRequest, reason: "\(group.groupType.lfgLabel) is locked; cannot post.")
		}
		// process image
		let filenames = try await processImages(data.images, usage: .groupPost, on: req)
		// create and save the new post, update groups' cached post count
		let effectiveAuthor = data.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let filename = filenames.count > 0 ? filenames[0] : nil
		let post = try GroupPost(group: group, authorID: effectiveAuthor.userID, text: data.text, image: filename)
		group.postCount += 1
		try await post.save(on: req.db)
		try await group.save(on: req.db)
		// If any participants block or mute this user, increase their hidden post count as they won't see this post.
		// The nice thing about doing it this way is most of the time there will be no blocks and nothing to do.
		var participantNotifyList: [UUID] = []
		for participantUserID in group.participantArray {
			guard let participantCacheUser = req.userCache.getUser(participantUserID) else {
				continue
			}
			if participantCacheUser.getBlocks().contains(effectiveAuthor.userID)
				|| participantCacheUser.getMutes().contains(effectiveAuthor.userID)
			{
				if let pivot = try await getUserPivot(group: group, userID: participantUserID, on: req.db) {
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
		if group.groupType != .closed {
			infoStr.append(" in \(group.groupType.lfgLabel) \"\(group.title)\".")
		}
		try await addNotifications(users: participantNotifyList, type: group.notificationType(), info: infoStr, on: req)
		try forwardPostToSockets(group, post, on: req)
		// A user posting is assumed to have read all prev posts. (even if this proves untrue, we should increment
		// readCount as they've read the post they just wrote!)
		if let pivot = try await getUserPivot(group: group, userID: cacheUser.userID, on: req.db) {
			pivot.readCount = group.postCount - pivot.hiddenCount
			try await pivot.save(on: req.db)
		}
		return try GroupPostData(post: post, author: effectiveAuthor.makeHeader())
	}

	/// `POST /api/v3/group/post/ID/delete`
	/// `DELETE /api/v3/group/post/ID`
	///
	/// Delete a `GroupPost`. Must be author of post.
	///
	/// - Parameter groupID: in URL path
	/// - Throws: 403 error if user is not the post author. 404 error if the group is not
	///   available. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: HTTP 204 No Content
	func postDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await GroupPost.findFromParameter(groupPostIDParam, on: req)
		try cacheUser.guardCanModifyContent(post)
		// get group and all its participant pivots. Also get count of posts before the one we're deleting.
		guard let group = try await post.$group.query(on: req.db).with(\.$participants.$pivots).first() else {
			throw Abort(.internalServerError, reason: "On delete: container for post not found")
		}
		guard !cacheUser.getBlocks().contains(group.$owner.id) else {
			throw Abort(.notFound, reason: "\(group.groupType.lfgLabel) is not available")
		}
		let postIndex = try await group.$groupPosts.query(on: req.db).filter(\.$id < post.requireID()).count()
		// delete post, reduce post count cached in group
		group.postCount -= 1
		try await group.save(on: req.db)
		try await post.delete(on: req.db)
		var adjustNotificationCountForUsers: [UUID] = []
		for participantPivot in group.$participants.pivots {
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
			type: group.notificationType(),
			on: req
		)
		try await post.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		return .noContent
	}

	/// `POST /api/v3/group/post/ID/report`
	///
	/// Creates a `Report` regarding the specified `GroupPost`.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter postID: in URL path, the ID of the post being reported.
	/// - Parameter requestBody: `ReportData` payload in the HTTP body.
	/// - Throws: 400 error if the post is private.
	/// - Throws: 404 error if the parent group of the post could not be found.
	/// - Returns: 201 Created on success.
	func reportGroupPostHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedPost = try await GroupPost.findFromParameter(groupPostIDParam, on: req)
		guard let reportedFriendlyGroup = try await FriendlyGroup.find(reportedPost.$group.id, on: req.db) else {
			throw Abort(.notFound, reason: "While trying to file report: could not find container for post")
		}
		guard reportedFriendlyGroup.groupType != GroupType.closed else {
			throw Abort(.badRequest, reason: "cannot report private (closed) posts")
		}
		return try await reportedPost.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: Group Management

	/// `POST /api/v3/group/create`
	///
	/// Create a `FriendlyGroup`. The creating user is automatically added to the participant list.
	///
	/// The list of recognized values for use in the `.groupType` field is obtained from
	/// `GET /api/v3/group/types`.
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
	/// - Parameter requestBody: `GroupContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: 201 Created; `GroupData` containing the newly created group.
	func createHandler(_ req: Request) async throws -> Response {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "User cannot create LFGs/Seamails.")
		// see `GroupContentData.validations()`
		let data = try ValidatingJSONDecoder().decode(GroupContentData.self, fromBodyOf: req)
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
		let group = FriendlyGroup(
			owner: creator.userID,
			groupType: data.groupType,
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
		guard data.groupType != .closed || initialUsers.count >= 2 else {
			throw Abort(.badRequest, reason: "Fewer than 2 users in seamail after applying user filters")
		}
		guard initialUsers.count >= 1 else {
			throw Abort(.badRequest, reason: "Cannot create \(group.groupType.lfgLabel) with 0 participants")
		}
		group.participantArray = initialUsers
		try await group.save(on: req.db)
		let participants = try await User.query(on: req.db).filter(\.$id ~~ initialUsers).all()
		try await group.$participants.attach(
			participants,
			on: req.db,
			{
				$0.readCount = 0
				$0.hiddenCount = 0
			}
		)
		let creatorPivot = try await group.$participants.$pivots.query(on: req.db).filter(\.$user.$id == creator.userID)
			.first()
		let groupData = try buildGroupData(from: group, with: creatorPivot, posts: [], for: user, on: req)
		// with 201 status
		let response = Response(status: .created)
		try response.content.encode(groupData)
		return response
	}

	/// `POST /api/v3/group/ID/cancel`
	///
	/// Cancel a FriendlyGroup. Owner only. Cancelling a Group is different from deleting it. A canceled group is still visible; members may still post to it.
	/// But, a cenceled group does not show up in searches for open groups, and should be clearly marked in UI to indicate that it's been canceled.
	///
	/// - Note: Eventually, cancelling a group should notifiy all members via the notifications endpoint.
	///
	/// - Parameter groupID: in URL path.
	/// - Throws: 403 error if user is not the group owner. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` with the updated group info.
	func cancelHandler(_ req: Request) async throws -> GroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard group.$owner.id == cacheUser.userID else {
			throw Abort(.forbidden, reason: "user does not own this \(group.groupType.lfgLabel)")
		}
		// FIXME: this should send out notifications
		group.cancelled = true
		try await group.save(on: req.db)
		let pivot = try await group.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.first()
		return try buildGroupData(from: group, with: pivot, for: cacheUser, on: req)
	}

	/// `POST /api/v3/group/ID/delete`
	/// `DELETE /api/v3/group/ID`
	///
	/// Delete the specified `FriendlyGroup`. This soft-deletes the group. Posts are left as-is.
	///
	/// To delete, the user must have an access level allowing them to delete the group. Currently this means moderators and above.
	/// The owner of a group may Cancel the group, which tells the members the group was cancelled, but does not delete it.
	///
	/// - Parameter groupID: in URL path.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func groupDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete an \(group.groupType.lfgLabel).")
		}
		try cacheUser.guardCanModifyContent(group)
		try await deleteGroupNotifications(userIDs: group.participantArray, group: group, on: req)
		try await group.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await group.$participants.detachAll(on: req.db).get()
		try await group.delete(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/group/ID/update`
	///
	/// Update the specified FriendlyGroup with the supplied data. Updating a cancelled group will un-cancel it.
	///
	/// - Note: All fields in the supplied `GroupContentData` must be filled, just as if the group
	///   were being created from scratch. If there is demand, using a set of more efficient
	///   endpoints instead of this single monolith can be considered.
	///
	/// - Parameter groupID: in URL path.
	/// - Parameter requestBody: `GroupContentData` payload in the HTTP body.
	/// - Throws: 400 error if the data is not valid. 403 error if user is not group owner.
	///   A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` containing the updated group info.
	func updateHandler(_ req: Request) async throws -> GroupData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// see GroupContentData.validations()
		let data = try ValidatingJSONDecoder().decode(GroupContentData.self, fromBodyOf: req)
		// get group
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		try cacheUser.guardCanModifyContent(group, customErrorString: "User cannot modify LFG")
		guard ![.closed, .open].contains(group.groupType) else {
			throw Abort(.forbidden, reason: "Cannot edit info on Seamail chats")
		}
		guard ![.closed, .open].contains(data.groupType) else {
			throw Abort(.forbidden, reason: "Cannot turn a LFG into a Seamail chat")
		}
		if data.title != group.title || data.location != group.location || data.info != group.info {
			let groupEdit = try FriendlyGroupEdit(group: group, editorID: cacheUser.userID)
			try await group.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
			try await groupEdit.save(on: req.db)
		}
		group.groupType = data.groupType
		group.title = data.title
		group.info = data.info
		group.startTime = data.startTime
		group.endTime = data.endTime
		group.location = data.location
		group.minCapacity = data.minCapacity
		group.maxCapacity = data.maxCapacity
		group.cancelled = false
		try await group.save(on: req.db)
		let pivot = try await getUserPivot(group: group, userID: cacheUser.userID, on: req.db)
		return try buildGroupData(from: group, with: pivot, for: cacheUser, on: req)
	}

	/// `POST /api/v3/group/ID/user/ID/add`
	///
	/// Add the specified `User` to the specified LFG or open chat. This lets the owner invite others.
	///
	/// - Parameter groupID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is already in barrel. 403 error if requester is not group
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` containing the updated group info.
	func userAddHandler(_ req: Request) async throws -> GroupData {
		let requester = try req.auth.require(UserCacheData.self)
		// get group and user to add
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard group.groupType != .closed else {
			throw Abort(.forbidden, reason: "Cannot add users to closed chat")
		}
		guard let userID = req.parameters.get(userIDParam.paramString, as: UUID.self),
			let cacheUser = req.userCache.getUser(userID)
		else {
			throw Abort(.forbidden, reason: "invalid user ID in request parameter")
		}
		guard group.$owner.id == requester.userID else {
			throw Abort(.forbidden, reason: "requester does not own \(group.groupType.lfgLabel)")
		}
		guard !group.participantArray.contains(userID) else {
			throw Abort(.badRequest, reason: "user is already in \(group.groupType.lfgLabel)")
		}
		guard !requester.getBlocks().contains(userID) else {
			throw Abort(.badRequest, reason: "user is not available")
		}
		group.participantArray.append(userID)
		let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
		let hiddenPostCount = try await group.$groupPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count()
		try await group.save(on: req.db)
		let newParticipant = try GroupParticipant(userID, group)
		newParticipant.readCount = 0
		newParticipant.hiddenCount = hiddenPostCount
		try await newParticipant.save(on: req.db)
		try forwardMembershipChangeToSockets(group, participantID: userID, joined: true, on: req)
		let effectiveUser = getEffectiveUser(user: requester, req: req, group: group)
		let pivot = try await group.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.first()
		return try buildGroupData(from: group, with: pivot, for: requester, on: req)
	}

	/// `POST /api/v3/group/ID/user/:userID/remove`
	///
	/// Remove the specified `User` from the specified FriendlyGroup barrel. This lets a group owner remove others.
	///
	/// - Parameter groupID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is not in the barrel. 403 error if requester is not group
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `GroupData` containing the updated group info.
	func userRemoveHandler(_ req: Request) async throws -> GroupData {
		let requester = try req.auth.require(UserCacheData.self)
		// get group and user to remove
		let removeUser = try await User.findFromParameter(userIDParam, on: req)
		let removeUserID = try removeUser.requireID()
		let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard group.groupType != .closed else {
			throw Abort(.forbidden, reason: "Cannot remove users from closed chat")
		}
		guard group.$owner.id == requester.userID else {
			throw Abort(.forbidden, reason: "requester does not own \(group.groupType.lfgLabel)")
		}
		// remove user
		guard let index = group.participantArray.firstIndex(of: removeUserID) else {
			throw Abort(.badRequest, reason: "user is not a member of this \(group.groupType.lfgLabel)")
		}
		group.participantArray.remove(at: index)
		try await group.save(on: req.db)
		try await group.$participants.detach(removeUser, on: req.db)
		try await deleteGroupNotifications(userIDs: [removeUserID], group: group, on: req)
		try forwardMembershipChangeToSockets(group, participantID: removeUserID, joined: false, on: req)
		let effectiveUser = getEffectiveUser(user: requester, req: req, group: group)
		let pivot = try await group.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.first()
		return try buildGroupData(from: group, with: pivot, for: requester, on: req)
	}

	/// `POST /api/v3/group/ID/report`
	///
	/// Creates a `Report` regarding the specified `Group`. This reports on the Group itself, not any of its posts in particular. This could mean a
	/// Group with reportable content in its Title, Info, or Location fields, or a bunch of reportable posts in the group.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter groupID: in URL path, the Group ID to report.
	/// - Parameter requestBody: `ReportData`
	/// - Returns: 201 Created on success.
	func reportGroupHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedGroup = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
		guard reportedGroup.groupType != .closed else {
			throw Abort(.forbidden, reason: "Cannot file reports on closed chats")
		}
		return try await reportedGroup.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: - Socket Functions

	/// `WS /api/v3/group/:groupID/socket`
	///
	/// Opens a websocket to receive updates on the given group. At the moment there's only 2 messages that the client may receive:
	/// - `SocketGroupPostData` - sent when a post is added to the group.
	/// - `SocketMemberChangeData` - sent when a member joins/leaves the group.
	///
	/// Note that there's a bunch of other state change that can happen with a group; I haven't built out code to send socket updates for them.
	/// The socket returned by this call is only intended for receiving updates; there are no client-initiated messages defined for this socket.
	/// Posting messages, leaving the group, updating or canceling the group and any other state changes should be performed using the various
	/// POST methods of this controller.
	///
	/// The server validates membership before sending out each socket message, but be sure to close the socket if the user leaves the group.
	/// This method is designed to provide updates only while a user is viewing the group in your app--don't open one of these sockets for each
	/// group a user joins and keep them open continually. Use `WS /api/v3/notification/socket` for long-term status updates.
	func createGroupSocket(_ req: Request, _ ws: WebSocket) async {
		do {
			let user = try req.auth.require(UserCacheData.self)
			let group = try await FriendlyGroup.findFromParameter(groupIDParam, on: req)
			guard userCanViewMemberData(user: user, group: group), let groupID = try? group.requireID() else {
				throw Abort(.badRequest, reason: "User can't vew messages in this LFG")
			}
			let userSocket = UserSocket(userID: user.userID, socket: ws, groupID: groupID, htmlOutput: false)
			try req.webSocketStore.storeGroupSocket(userSocket)

			ws.onClose.whenComplete { result in
				try? req.webSocketStore.removeGroupSocket(userSocket)
			}
		}
		catch {
			try? await ws.close()
		}
	}

	// Checks for sockets open on this group, and sends the post to each of them.
	func forwardPostToSockets(_ group: FriendlyGroup, _ post: GroupPost, on req: Request) throws {
		try req.webSocketStore.getGroupSockets(group.requireID())
			.forEach { userSocket in
				let postAuthor = try req.userCache.getHeader(post.$author.id)
				guard let socketOwner = req.userCache.getUser(userSocket.userID),
					userCanViewMemberData(user: socketOwner, group: group),
					!(socketOwner.getBlocks().contains(postAuthor.userID)
						|| socketOwner.getMutes().contains(postAuthor.userID))
				else {
					return
				}
				var leafPost = try SocketGroupPostData(post: post, author: postAuthor)
				if userSocket.htmlOutput {
					struct GroupPostContext: Encodable {
						var userID: UUID
						var groupPost: SocketGroupPostData
						var showModButton: Bool
					}
					let ctx = GroupPostContext(
						userID: userSocket.userID,
						groupPost: leafPost,
						showModButton: socketOwner.accessLevel.hasAccess(.moderator) && group.groupType != .closed
					)
					_ = req.view.render("Group/groupPost", ctx)
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

	// Checks for sockets open on this group, and sends the membership change info to each of them.
	func forwardMembershipChangeToSockets(_ group: FriendlyGroup, participantID: UUID, joined: Bool, on req: Request) throws
	{
		try req.webSocketStore.getGroupSockets(group.requireID())
			.forEach { userSocket in
				let participantHeader = try req.userCache.getHeader(participantID)
				guard let socketOwner = req.userCache.getUser(userSocket.userID),
					userCanViewMemberData(user: socketOwner, group: group),
					!socketOwner.getBlocks().contains(participantHeader.userID)
				else {
					return
				}
				var change = SocketGroupMemberChangeData(user: participantHeader, joined: joined)
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

extension GroupController {

	// MembersOnlyData is only filled in if:
	//	* The user is a member of the group (pivot is not nil) OR
	//  * The user is a moderator and the group is not private
	//
	// Pivot should always be nil if the current user is not a member of the group.
	// To read the 'moderator' or 'twitarrteam' seamail, verify the requestor has access and call this fn with
	// the effective user's account.
	func buildGroupData(
		from group: FriendlyGroup,
		with pivot: GroupParticipant? = nil,
		posts: [GroupPostData]? = nil,
		for cacheUser: UserCacheData,
		on req: Request
	) throws -> GroupData {
		let userBlocks = cacheUser.getBlocks()
		// init return struct
		let ownerHeader = try req.userCache.getHeader(group.$owner.id)
		var groupData: GroupData = try GroupData(group: group, owner: ownerHeader)
		if pivot != nil || (cacheUser.accessLevel.hasAccess(.moderator) && group.groupType != .closed) {
			let allParticipantHeaders = req.userCache.getHeaders(group.participantArray)

			// masquerade blocked users
			let valids = allParticipantHeaders.map { (member: UserHeader) -> UserHeader in
				if userBlocks.contains(member.userID) {
					return UserHeader.Blocked
				}
				return member
			}
			// populate groupData's participant list and waiting list
			var participants: [UserHeader]
			var waitingList: [UserHeader]
			if valids.count > group.maxCapacity && group.maxCapacity > 0 {
				participants = Array(valids[valids.startIndex..<group.maxCapacity])
				waitingList = Array(valids[group.maxCapacity..<valids.endIndex])
			}
			else {
				participants = valids
				waitingList = []
			}
			groupData.members = GroupData.MembersOnlyData(
				participants: participants,
				waitingList: waitingList,
				postCount: group.postCount - (pivot?.hiddenCount ?? 0),
				readCount: pivot?.readCount ?? 0,
				posts: posts
			)
		}
		return groupData
	}

	// Remember that there can be posts by authors who are not currently participants.
	func buildPostsForGroup(_ group: FriendlyGroup, pivot: GroupParticipant?, on req: Request, user: UserCacheData) async throws
		-> ([GroupPostData], Paginator)
	{
		let readCount = pivot?.readCount ?? 0
		let hiddenCount = pivot?.hiddenCount ?? 0
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let start = (req.query[Int.self, at: "start"] ?? ((readCount - 1) / limit) * limit)
			.clamped(to: 0...group.postCount)
		// get posts
		let posts = try await GroupPost.query(on: req.db)
			.filter(\.$group.$id == group.requireID())
			.filter(\.$author.$id !~ user.getBlocks())
			.filter(\.$author.$id !~ user.getMutes())
			.sort(\.$createdAt, .ascending)
			.range(start..<(start + limit))
			.all()
		let postDatas = try posts.map { try GroupPostData(post: $0, author: req.userCache.getHeader($0.$author.id)) }
		let paginator = Paginator(total: group.postCount - hiddenCount, start: start, limit: limit)

		// If this batch of posts is farther into the thread than the user has previously read, increase
		// the user's read count.
		if let pivot = pivot, start + limit > pivot.readCount {
			pivot.readCount = min(start + limit, group.postCount - pivot.hiddenCount)
			try await pivot.save(on: req.db)
			// If the user has now read all the posts (except those hidden from them) mark this notification as viewed.
			if pivot.readCount + pivot.hiddenCount >= group.postCount {
				try await markNotificationViewed(user: user, type: group.notificationType(), on: req)
			}
		}
		return (postDatas, paginator)
	}

	func getUserPivot(group: FriendlyGroup, userID: UUID, on db: Database) async throws -> GroupParticipant? {
		return try await group.$participants.$pivots.query(on: db).filter(\.$user.$id == userID).first()
	}

	func userCanViewMemberData(user: UserCacheData, group: FriendlyGroup) -> Bool {
		return user.accessLevel.hasAccess(.moderator) || group.participantArray.contains(user.userID)
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

	// This version of getEffectiveUser checks the user against the group's membership, and also checks whether
	// user 'moderator' or user 'TwitarrTeam' is a member of the group and the user has the appropriate access level.
	//
	func getEffectiveUser(user: UserCacheData, req: Request, group: FriendlyGroup) -> UserCacheData {
		if group.participantArray.contains(user.userID) {
			return user
		}
		// If either of these 'special' users are group members and the user has high enough access, we can see the
		// members-only values of the group as the 'special' user.
		if user.accessLevel >= .twitarrteam, let ttUser = req.userCache.getUser(username: "TwitarrTeam"),
			group.participantArray.contains(ttUser.userID)
		{
			return ttUser
		}
		if user.accessLevel >= .moderator, let modUser = req.userCache.getUser(username: "moderator"),
			group.participantArray.contains(modUser.userID)
		{
			return modUser
		}
		// User isn't a member of the group, but they're still the effective user in this case.
		return user
	}
}
