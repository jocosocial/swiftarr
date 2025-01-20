import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/fez/*` route endpoints and handler functions related to Looking For Group and Seamail chats.
struct FezController: APIRouteCollection {

	// A struct with common URL query parameters for routes in the Fez Controller.
	// Most route handlers don't actually use all these options; each handler's header comment
	// specifies what URL options it uses.
	// The decode() call decodes the URL Query into this struct; trying to decode keys the the handler doesn't use
	// doesn't matter; whether or not the URL Query contains the option or not. However, it is possible a malformed
	// but unused query parameter would result in an error for the call.
	struct FezURLQueryStruct: Content {
		var type: [String] = []
		var excludetype: [String] = []
		var lfgtypes: Bool?
		var onlynew: Bool?
		var start: Int?
		var limit: Int?
		var cruiseday: Int?
		var search: String?
		var hidePast: Bool?
		var matchID: UUID?

		func getTypes() throws -> [FezType]? {
			var includeTypes = try type.map { try FezType.fromAPIString($0) }
			if lfgtypes == true { 
				includeTypes.append(contentsOf: FezType.lfgTypes) 
			}
			includeTypes = Array(Set(includeTypes))
			return includeTypes.count > 0 ? includeTypes : nil
		}

		func getExcludeTypes() throws -> [FezType]? {
			var excludeTypes = try excludetype.map { try FezType.fromAPIString($0) }
			if lfgtypes == false { 
				excludeTypes.append(contentsOf: FezType.lfgTypes) 
			}
			excludeTypes = Array(Set(excludeTypes))
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

		// convenience route group for all /api/v3/fez endpoints
		let fezRoutes = app.grouped("api", "v3", "fez")

		// Open access routes
		let flexAuthGroup = fezRoutes.flexRoutes(feature: .friendlyfez)
		flexAuthGroup.get("types", use: typesHandler)

		// endpoints available only when logged in
		let tokenAuthGroup = fezRoutes.tokenRoutes(feature: .friendlyfez)
		tokenAuthGroup.get("open", use: openHandler)
		tokenAuthGroup.get("joined", use: joinedHandler)
		tokenAuthGroup.get("owner", use: ownerHandler)
		tokenAuthGroup.get(fezIDParam, use: fezHandler)
		tokenAuthGroup.post("create", use: createHandler)
		tokenAuthGroup.on(.POST, fezIDParam, "post", body: .collect(maxSize: "30mb"), use: postAddHandler)
		tokenAuthGroup.webSocket(fezIDParam, "socket", onUpgrade: createFezSocket)
		tokenAuthGroup.post(fezIDParam, "cancel", use: cancelHandler)
		tokenAuthGroup.post(fezIDParam, "join", use: joinHandler)
		tokenAuthGroup.post(fezIDParam, "unjoin", use: unjoinHandler)
		tokenAuthGroup.post("post", fezPostIDParam, "delete", use: postDeleteHandler)
		tokenAuthGroup.delete("post", fezPostIDParam, use: postDeleteHandler)
		tokenAuthGroup.post(fezIDParam, "user", userIDParam, "add", use: userAddHandler)
		tokenAuthGroup.post(fezIDParam, "user", userIDParam, "remove", use: userRemoveHandler)
		tokenAuthGroup.post(fezIDParam, "update", use: updateHandler)
		tokenAuthGroup.post(fezIDParam, "delete", use: fezDeleteHandler)
		tokenAuthGroup.delete(fezIDParam, use: fezDeleteHandler)
		tokenAuthGroup.post(fezIDParam, "report", use: reportFezHandler)
		tokenAuthGroup.get("former", use: formerlyJoinedFezHandler)
		tokenAuthGroup.post("post", fezPostIDParam, "report", use: reportFezPostHandler)
		tokenAuthGroup.post(fezIDParam, "mute", use: muteAddHandler)
		tokenAuthGroup.delete(fezIDParam, "mute", use: muteRemoveHandler)
		tokenAuthGroup.post(fezIDParam, "mute", "remove", use: muteRemoveHandler)
	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

	// MARK: Retrieving Fezzes

	/// `/GET /api/v3/fez/types`
	///
	/// Retrieve a list of all values for `FezType` as strings.
	///
	/// - Returns: An array of `String` containing the `.label` value for each type.
	func typesHandler(_ req: Request) throws -> [String] {
		return FezType.allCases.map { $0.label }
	}

	/// `GET /api/v3/fez/open`
	///
	/// Retrieve FriendlyFezzes with open slots and a startTime of no earlier than one hour ago. Results are returned sorted by start time, then by title.
	///
	/// **URL Query Parameters:**
	///
	/// * `?cruiseday=INT` - Only return fezzes occuring on this day of the cruise. Embarkation Day is day 0.
	/// * `?type=STRING` - Only return fezzes of this type, there STRING is a `FezType.fromAPIString()` string.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of fezzes to return; defaults to 50.
	/// - `?hidepast=BOOLEAN` - Show fezzes that started more than one hour in the past. For this endpoint, this defaults to TRUE.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `FezData` containing current fezzes with open slots.
	func openHandler(_ req: Request) async throws -> FezListData {
		let urlQuery = try req.query.decode(FezURLQueryStruct.self)
		let cacheUser = try req.auth.require(UserCacheData.self)

		let fezQuery = FriendlyFez.query(on: req.db)
			.filter(\.$fezType ~~ FezType.lfgTypes)
			.filter(\.$owner.$id !~ cacheUser.getBlocks())
			.filter(\.$cancelled == false)

		if urlQuery.hidePast ?? true {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			fezQuery.filter(\.$startTime > searchStartTime)
		}

		if let typeFilter = try urlQuery.getTypes() {
			fezQuery.filter(\.$fezType ~~ typeFilter)
		}
		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			let threeAMCutoff =
				portCalendar.date(byAdding: .hour, value: 3, to: Settings.shared.cruiseStartDate())
				?? Settings.shared.cruiseStartDate()
			let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: threeAMCutoff) ?? threeAMCutoff
			let dayEnd = portCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
			fezQuery.filter(\.$startTime >= dayStart).filter(\.$startTime < dayEnd)
		}
		if var searchStr = urlQuery.search {
			searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			fezQuery.group(.or) { group in
				group.fullTextFilter(FriendlyFez.self, \.$title, searchStr)
					.fullTextFilter(FriendlyFez.self, \.$info, searchStr)
			}
		}
		let fezCount = try await fezQuery.count()
		let fezzes = try await fezQuery.sort(\.$startTime, .ascending).sort(\.$title, .ascending)
			.range(urlQuery.calcRange()).all()
		let fezDataArray: [FezData] = try fezzes.compactMap { fez in
			// Fezzes are only 'open' if their waitlist is < 1/2 the size of their capacity. A fez with a max of 10 people
			// could have a waitlist of 5, then it stops showing up in 'open' searches.
			if (fez.maxCapacity == 0 || fez.participantArray.count < Int(Double(fez.maxCapacity) * 1.5))
				&& !fez.participantArray.contains(cacheUser.userID)
			{
				return try buildFezData(from: fez, with: nil, for: cacheUser, on: req)
			}
			return nil
		}
		return FezListData(
			paginator: Paginator(total: fezCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()),
			fezzes: fezDataArray
		)
	}

	/// `GET /api/v3/fez/joined`
	///
	/// Retrieve all the FriendlyFez chats that the user has joined. Results are sorted by descending fez update time.
	///
	/// **Query Parameters:**
	/// * `?cruiseday=INT` - Only return fezzes occuring on this day of the cruise. Embarkation Day is day 0.
	/// - `?type=STRING` - Only return fezzes of the given fezType. See `FezType` for a list.
	/// - `?excludetype=STRING` - Don't return fezzes of the given type. See `FezType` for a list.
	/// - `?onlynew=TRUE` - Only return fezzes with unread messages.
	/// - `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// - `?limit=INT` - The maximum number of fezzes to return; defaults to 50.
	/// - `?search=STRING` - Only show fezzes whose title, info, or any post contains the given string.
	/// - `?hidepast=BOOLEAN` - Hide fezzes that started more than one hour in the past. For this endpoint, this defaults to FALSE.
	/// - `?matchID=UUID` - Returns a single LFG with the given ID.
	/// - `?lfgtypes=BOOLEAN` - Shorthand to include/exliude all the LFG types (Activity, Gaming, Dining, etc.) Acts the same as using multiple `type=` or `exludetype=` params.
	///
	/// Moderators and above can use the `foruser` query parameter to access pseudo-accounts:
	///
	/// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	///
	/// `/GET /api/v3/fez/types` is  the canonical way to get the list of acceptable values. Type and excludetype are exclusive options, obv.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `FezData` containing all the fezzes joined by the user.
	func joinedHandler(_ req: Request) async throws -> FezListData {
		let urlQuery = try req.query.decode(FezURLQueryStruct.self)
		return try await getJoinedChats(req, urlQuery: urlQuery)
	}
	
	/// `GET /api/v3/fez/owner`
	///
	/// Retrieve the FriendlyFez chats created by the user.
	///
	/// - Note: There is no block filtering on this endpoint. In theory, a block could only
	///   apply if it were set *after* the fez had been joined by the second party. The
	///   owner of the fez has the ability to remove users if desired, and the fez itself is no
	///   longer visible to the non-owning party.
	///
	/// **Query Parameters:**
	/// * `?cruiseday=INT` - Only return fezzes occuring on this day of the cruise. Embarkation Day is day 0.
	/// - `?type=STRING` - Only return fezzes of the given fezType. See `FezType` for a list.
	/// - `?excludetype=STRING` - Don't return fezzes of the given type. See `FezType` for a list.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of fezzes to return; defaults to 50.
	/// - `?hidepast=BOOLEAN` - Hide fezzes that started more than one hour in the past. For this endpoint, this defaults to FALSE.
	/// - `?lfgtypes=BOOLEAN` - Shorthand to include/exliude all the LFG types (Activity, Gaming, Dining, etc.) Acts the same as using multiple `type=` or `exludetype=` params.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `FezData` containing all the fezzes created by the user.
	func ownerHandler(_ req: Request) async throws -> FezListData {
		let urlQuery = try req.query.decode(FezURLQueryStruct.self)
		let user = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = FriendlyFez.query(on: req.db).filter(\.$owner.$id == user.userID)
			.join(FezParticipant.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
			.filter(FezParticipant.self, \.$user.$id == user.userID)
		if let includeTypes = try urlQuery.getTypes() {
			query.filter(\.$fezType ~~ includeTypes)
		}
		else if let excludeTypes = try urlQuery.getExcludeTypes() {
			query.filter(\.$fezType !~ excludeTypes)
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

		if var searchStr = urlQuery.search {
			searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			query.group(.or) { group in
				group.fullTextFilter(FriendlyFez.self, \.$title, searchStr)
					.fullTextFilter(FriendlyFez.self, \.$info, searchStr)
			}
		}

		// get owned fezzes
		let fezCount = try await query.count()
		let fezzes = try await query.range(start..<(start + limit)).sort(\.$createdAt, .descending).all()
		// convert to FezData
		let fezDataArray = try fezzes.map { (fez) -> FezData in
			let userParticipant = try fez.joined(FezParticipant.self)
			return try buildFezData(from: fez, with: userParticipant, for: user, on: req)
		}
		return FezListData(paginator: Paginator(total: fezCount, start: start, limit: limit), fezzes: fezDataArray)
	}

	/// `GET /api/v3/fez/:fez_ID`
	///
	/// Retrieve information about the specified FriendlyFez. For users that aren't members of the fez, this info will be the same as
	/// the info returned for `GET /api/v3/fez/open`. For users that have joined the fez the `FezData.MembersOnlyData` will be populated, as will
	/// the `FezPost`s.
	///
	/// **Query Parameters:**
	/// * `?start=INT` - The offset to the first post to return in the array of posts.
	/// * `?limit=INT` - The maximum number of posts to return; defaults to 50.
	///
	/// Start and limit only have an effect when the user is a member of the Fez. Limit defaults to 50 and start defaults to `(readCount / limit) * limit`,
	/// where readCount is how many posts the user has read already.
	///
	/// Moderators and above can use the `foruser` query parameter to access pseudo-accounts:
	///
	/// - `?foruser=NAME` - Access the "moderator" or "twitarrteam" seamail accounts.
	///
	/// When a member calls this method, it updates the member's `readCount`, marking all posts read up to `start + limit`.
	/// However, the returned readCount is the value before updating. If there's 5 posts in the chat, and the member has read 3 of them, the returned
	/// `FezData` has 5 posts, we return 3 in `FezData.readCount`field, and update the pivot's readCount to 5.
	///
	/// `FezPost`s are ordered by creation time.
	///
	/// - Note: Posts are subject to block and mute user filtering, but mutewords are ignored
	///   in order to not suppress potentially important information.
	///
	/// - Parameter fezID: in the URL path.
	/// - Throws: 404 error if a block between the user and fez owner applies. A 5xx response
	///   should be reported as a likely bug, please and thank you.
	/// - Returns: `FezData` with fez info and all discussion posts.
	func fezHandler(_ req: Request) async throws -> FezData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		let effectiveUser = getEffectiveUser(user: cacheUser, req: req, fez: fez)
		guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
			throw Abort(.notFound, reason: "this \(fez.fezType.lfgLabel) is not available")
		}
		let pivot = try await fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID).first()
		var fezData = try buildFezData(from: fez, with: pivot, for: cacheUser, on: req)
		if let _ = fezData.members {
			let (posts, paginator) = try await buildPostsForFez(fez, pivot: pivot, on: req, user: cacheUser, as: effectiveUser)
			fezData.members?.paginator = paginator
			fezData.members?.posts = posts
		}
		return fezData
	}
	
	/// `GET /api/v3/fez/former`
	/// 
	/// **Query Parameters:**
	/// * `?start=INT` - The offset to the first post to return in the array of posts.
	/// * `?limit=INT` - The maximum number of posts to return; defaults to 50.
	///
	/// Retrieve information about (open) Seamails, Private Events, and LFGs  the user was previously a member of, but no longer.  Won't return info on 
	/// closed Seamails or Personal Events as their member lists cannot change.
	func formerlyJoinedFezHandler(_ req: Request) async throws -> FezListData {
		let urlQuery = try req.query.decode(FezURLQueryStruct.self)
		let cacheUser = try req.auth.require(UserCacheData.self)
		let effectiveUser = try getEffectiveUser(user: cacheUser, req: req)
		// .withDeleted keeps Fluent from filtering out soft-deleted FriendlyFezzes and FezParticipants. The deletedAt filter then matches
		// FezParticipants that have been soft-deleted only. We want fezzes that have been soft-deleted to be in the found set.
		let query = FezParticipant.query(on: req.db).join(FriendlyFez.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
				.filter(\.$user.$id == effectiveUser.userID)
				.filter(FriendlyFez.self, \.$fezType !~ [.closed, .personalEvent])
				.withDeleted().filter(\.$deletedAt < Date())
		let fezCount = try await query.count()
		let pivots = try await query.copy().sort(FriendlyFez.self, \.$createdAt, .descending).range(urlQuery.calcRange()).all()
		let fezDataArray = try pivots.map { pivot -> FezData in
			let fez = try pivot.joined(FriendlyFez.self)
			return try buildFezData(from: fez, with: nil, for: effectiveUser, on: req)
		}
		return FezListData(paginator: Paginator(total: fezCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()), fezzes: fezDataArray)
	}

	// MARK: Membership

	/// `POST /api/v3/fez/ID/join`
	///
	/// Add the current user to the FriendlyFez. If the `.maxCapacity` of the fez has been
	/// reached, the user is added to the waiting list.
	///
	/// - Note: A user cannot join a fez that is owned by a blocked or blocking user. If any
	///   current participating or waitList user is in the user's blocks, their identity is
	///   replaced by a placeholder in the returned data. It is the user's responsibility to
	///   examine the participant list for conflicts prior to joining or attending.
	///
	/// - Parameter fezID: in the URL path.
	/// - Throws: 400 error if the supplied ID is not a fez barrel or user is already in fez.
	///   404 error if a block between the user and fez owner applies. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `FezData` containing the updated fez data.
	func joinHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		switch fez.fezType {
			case .closed: throw Abort(.badRequest, reason: "Cannot add members to a closed chat")
			case .open: throw Abort(.badRequest, reason: "Cannot add yourself to a Seamail chat. Ask the chat creator to add you.")
			case .personalEvent: throw Abort(.badRequest, reason: "Cannot add members to a personal event")
			case .privateEvent: throw Abort(.badRequest, reason: "Cannot add yourself to a Private Event. Ask the event creator to add you.")
			default: break
		}
		guard !fez.participantArray.contains(cacheUser.userID) else {
			throw Abort(.notFound, reason: "user is already a member of this \(fez.fezType.lfgLabel)")
		}
		// respect blocks
		guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
			throw Abort(.notFound, reason: "This \(fez.fezType.lfgLabel) is not available")
		}
		// add user to both the participantArray and attach a pivot for them.
		fez.participantArray.append(cacheUser.userID)
		try await fez.save(on: req.db)
		let newParticipant = try await getUserPivotForAdd(lfg: fez, userID: cacheUser.userID, on: req.db)
		newParticipant.readCount = 0
		let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
		newParticipant.hiddenCount = try await fez.$fezPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes)
			.count()
		try await newParticipant.save(on: req.db)
		try await forwardMembershipChangeToSockets(fez, participantID: cacheUser.userID, joined: true, on: req)
		let fezData = try buildFezData(from: fez, with: newParticipant, for: cacheUser, on: req)
		_ = try await storeNextJoinedAppointment(userID: cacheUser.userID, on: req)
		// return with 201 status
		let response = Response(status: .created)
		try response.content.encode(fezData)
		return response
	}

	/// `POST /api/v3/fez/ID/unjoin`
	///
	/// Remove the current user from the FriendlyFez. If the `.maxCapacity` of the fez had
	/// previously been reached, the first user from the waiting list, if any, is moved to the
	/// participant list.
	///
	/// - Parameter fezID: in the URL path.
	/// - Throws: 400 error if the supplied ID is not a fez barrel. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `FezData` containing the updated fez data.
	func unjoinHandler(_ req: Request) async throws -> FezData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard fez.fezType != .closed else {
			throw Abort(.badRequest, reason: "Cannot remove members to a closed chat")
		}
		// Don't allow privileged users looking at a privileged mailbox to attempt to remove
		// the privileged user from a Chat. Without this check their removal action will silently
		// be a no-op.
		if cacheUser.accessLevel.hasAccess(.moderator), !fez.participantArray.contains(cacheUser.userID) {
			throw Abort(.badRequest, reason: "Privileged users cannot leave a chat they are not part of themselves")
		}
		// Save a FezEditRecord containing the participant list before removal
		let fezEdit = try FriendlyFezEdit(fez: fez, editorID: cacheUser.userID)
		try await fezEdit.save(on: req.db)
		// remove user from participantArray and also remove the pivot.
		if let index = fez.participantArray.firstIndex(of: cacheUser.userID) {
			fez.participantArray.remove(at: index)
		}
		try await fez.save(on: req.db)
		try await fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).delete()
		try await deleteFezNotifications(userIDs: [cacheUser.userID], fez: fez, on: req)
		try await forwardMembershipChangeToSockets(fez, participantID: cacheUser.userID, joined: false, on: req)
		_ = try await storeNextJoinedAppointment(userID: cacheUser.userID, on: req)
		return try buildFezData(from: fez, with: nil, for: cacheUser, on: req)
	}

	// MARK: Posts

	/// `POST /api/v3/fez/ID/post`
	///
	/// Add a `FezPost` to the specified `FriendlyFez`.
	///
	/// Open fez types are only permitted to have 1 image per post. Private fezzes (aka Seamail) cannot have any images.
	///
	/// - Parameter fezID: in URL path
	/// - Parameter requestBody: `PostContentData`
	/// - Throws: 404 error if the fez is not available. A 5xx response should be reported
	///   as a likely bug, please and thank you.
	/// - Returns: `FezPostData` containing the user's new post.
	func postAddHandler(_ req: Request) async throws -> FezPostData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()
		// see PostContentData.validations()
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard fez.fezType != .personalEvent else {
			throw Abort(.badRequest, reason: "Personal Events don't have posts.")
		}
		guard ![.closed, .open].contains(fez.fezType) || data.images.count == 0 else {
			throw Abort(.badRequest, reason: "Private conversations can't contain photos.")
		}
		guard data.images.count <= 1 else {
			throw Abort(.badRequest, reason: "posts may only have one image")
		}
		guard fez.participantArray.contains(cacheUser.userID) || cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "user is not member of \(fez.fezType.lfgLabel); cannot post")
		}
		guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
			throw Abort(.notFound, reason: "\(fez.fezType.lfgLabel) is not available")
		}
		guard fez.moderationStatus != .locked else {
			// Note: Users should still be able to post in a quarantined LFG so they can figure out what (else) to do.
			throw Abort(.badRequest, reason: "\(fez.fezType.lfgLabel) is locked; cannot post.")
		}
		// process image
		let filenames = try await processImages(data.images, usage: .fezPost, on: req)
		// create and save the new post, update fezzes' cached post count
		let effectiveAuthor = data.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let filename = filenames.count > 0 ? filenames[0] : nil
		let post = try FezPost(fez: fez, authorID: effectiveAuthor.userID, text: data.text, image: filename)
		fez.postCount += 1
		try await post.save(on: req.db)
		try await fez.save(on: req.db)
		// If any participants block or mute this user, increase their hidden post count as they won't see this post.
		// The nice thing about doing it this way is most of the time there will be no blocks and nothing to do.
		var participantNotifyList: [UUID] = []
		for participantUserID in fez.participantArray {
			guard let participantCacheUser = req.userCache.getUser(participantUserID) else {
				continue
			}
			if participantCacheUser.getBlocks().contains(effectiveAuthor.userID)
				|| participantCacheUser.getMutes().contains(effectiveAuthor.userID)
			{
				if let pivot = try await getUserPivot(lfg: fez, userID: participantUserID, on: req.db) {
					pivot.hiddenCount += 1
					try await pivot.save(on: req.db)
				}
			}
			else if participantUserID != cacheUser.userID {
				if let pivot = try await getUserPivot(lfg: fez, userID: participantUserID, on: req.db), pivot.isMuted == true {
					continue
				}
				participantNotifyList.append(participantUserID)
			}
		}
		try await post.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		var infoStr = "@\(effectiveAuthor.username) wrote, \"\(post.text)\""
		if fez.fezType != .closed {
			infoStr.append(" in \(fez.fezType.lfgLabel) \"\(fez.title)\".")
		}
		try await addNotifications(users: participantNotifyList, type: .chatUnreadMsg(fez.requireID(), fez.fezType), info: infoStr, creatorID: cacheUser.userID, on: req)
		try await forwardPostToSockets(fez, post, on: req)
		// A user posting is assumed to have read all prev posts. (even if this proves untrue, we should increment
		// readCount as they've read the post they just wrote!)
		if let pivot = try await getUserPivot(lfg: fez, userID: cacheUser.userID, on: req.db) {
			pivot.readCount = fez.postCount - pivot.hiddenCount
			try await pivot.save(on: req.db)
		}
		return try FezPostData(post: post, author: effectiveAuthor.makeHeader())
	}

	/// `POST /api/v3/fez/post/ID/delete`
	/// `DELETE /api/v3/fez/post/ID`
	///
	/// Delete a `FezPost`. Must be author of post.
	///
	/// - Parameter fezID: in URL path
	/// - Throws: 403 error if user is not the post author. 404 error if the fez is not
	///   available. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: HTTP 204 No Content
	func postDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await FezPost.findFromParameter(fezPostIDParam, on: req)
		try cacheUser.guardCanModifyContent(post)
		// get fez and all its participant pivots. Also get count of posts before the one we're deleting.
		guard let fez = try await post.$fez.query(on: req.db).with(\.$participants.$pivots).first() else {
			throw Abort(.internalServerError, reason: "On delete: container for post not found")
		}
		guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
			throw Abort(.notFound, reason: "\(fez.fezType.lfgLabel) is not available")
		}
		let postIndex = try await fez.$fezPosts.query(on: req.db).filter(\.$id < post.requireID()).count()
		// delete post, reduce post count cached in fez
		fez.postCount -= 1
		try await fez.save(on: req.db)
		try await post.delete(on: req.db)
		var adjustNotificationCountForUsers: [UUID] = []
		for participantPivot in fez.$participants.pivots {
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
		_ = try await subtractNotifications(users: adjustNotificationCountForUsers, type: .chatUnreadMsg(fez.requireID(), fez.fezType), on: req)
		try await post.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		return .noContent
	}

	/// `POST /api/v3/fez/post/ID/report`
	///
	/// Creates a `Report` regarding the specified `FezPost`.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter postID: in URL path, the ID of the post being reported.
	/// - Parameter requestBody: `ReportData` payload in the HTTP body.
	/// - Throws: 400 error if the post is private.
	/// - Throws: 404 error if the parent fez of the post could not be found.
	/// - Returns: 201 Created on success.
	func reportFezPostHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedPost = try await FezPost.findFromParameter(fezPostIDParam, on: req)
		guard let reportedFriendlyFez = try await FriendlyFez.find(reportedPost.$fez.id, on: req.db) else {
			throw Abort(.notFound, reason: "While trying to file report: could not find container for post")
		}
		guard reportedFriendlyFez.fezType != FezType.closed else {
			throw Abort(.badRequest, reason: "cannot report private (closed) posts")
		}
		return try await reportedPost.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: Fez Management

	/// `POST /api/v3/fez/create`
	///
	/// Create a `FriendlyFez`. The creating user is automatically added to the participant list.
	///
	/// The list of recognized values for use in the `.fezType` field is obtained from
	/// `GET /api/v3/fez/types`.
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
	/// - Parameter requestBody: `FezContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: 201 Created; `FezData` containing the newly created fez.
	func createHandler(_ req: Request) async throws -> Response {
		let data: FezContentData = try ValidatingJSONDecoder().decode(FezContentData.self, fromBodyOf: req)
		let apptData =  try await createChat(req, data: data)
		let response = Response(status: .created)
		try response.content.encode(apptData)
		return response
	}
	
	/// `POST /api/v3/fez/ID/cancel`
	///
	/// Cancel a FriendlyFez. Owner only. Cancelling a Fez is different from deleting it. A canceled fez is still visible; members may still post to it.
	/// But, a cenceled fez does not show up in searches for open fezzes, and should be clearly marked in UI to indicate that it's been canceled.
	///
	/// - Parameter fezID: in URL path.
	/// - Throws: 403 error if user is not the fez owner. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: `FezData` with the updated fez info.
	func cancelHandler(_ req: Request) async throws -> FezData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard fez.$owner.id == cacheUser.userID else {
			throw Abort(.forbidden, reason: "user does not own this \(fez.fezType.lfgLabel)")
		}
		fez.cancelled = true
		try await fez.save(on: req.db)
		for fezParticipant in fez.participantArray {
			_ = try await storeNextJoinedAppointment(userID: fezParticipant, on: req)
		}
		let cancelNotifyTargets = fez.participantArray.filter { $0 != cacheUser.userID }
			try await addNotifications(users: cancelNotifyTargets, type: .chatCanceled(fez.requireID(), fez.fezType), info: "\(fez.title) has been canceled", on: req)
		let pivot = try await fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.first()
		return try buildFezData(from: fez, with: pivot, for: cacheUser, on: req)
	}

	/// `POST /api/v3/fez/ID/delete`
	/// `DELETE /api/v3/fez/ID`
	///
	/// Delete the specified `FriendlyFez`. This soft-deletes the fez. Posts are left as-is.
	///
	/// To delete, the user must have an access level allowing them to delete the fez. Currently this means moderators and above.
	/// The owner of a fez may Cancel the fez, which tells the members the fez was cancelled, but does not delete it.
	/// However, a Personal Event can be deleted by its creator, as that LFG type doesn't allow participants to be added to it.
	///
	/// - Parameter fezID: in URL path.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func fezDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard fez.fezType == .personalEvent || cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete an \(fez.fezType.lfgLabel).")
		}
		try cacheUser.guardCanModifyContent(fez)
		try await deleteFezNotifications(userIDs: fez.participantArray, fez: fez, on: req)
		try await fez.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await fez.$participants.detachAll(on: req.db).get()
		try await fez.delete(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/fez/ID/update`
	///
	/// Update the specified FriendlyFez with the supplied data. Updating a cancelled fez will un-cancel it.
	/// Does not process the initialUsers field; use the user add/remove routes to change the participants.
	///
	/// - Note: All fields in the supplied `FezContentData` must be filled, just as if the fez
	///   were being created from scratch. If there is demand, using a set of more efficient
	///   endpoints instead of this single monolith can be considered.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter requestBody: `FezContentData` payload in the HTTP body.
	/// - Throws: 400 error if the data is not valid. 403 error if user is not fez owner.
	///   A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezData` containing the updated fez info.
	func updateHandler(_ req: Request) async throws -> FezData {
		// see FezContentData.validations()
		let data = try ValidatingJSONDecoder().decode(FezContentData.self, fromBodyOf: req)
		return try await updateChat(req, data: data)
	}

	/// `POST /api/v3/fez/ID/user/ID/add`
	///
	/// Add the specified `User` to the specified LFG or open chat. This lets the owner invite others.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is already in barrel. 403 error if requester is not fez
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezData` containing the updated fez info.
	func userAddHandler(_ req: Request) async throws -> FezData {
		let requester = try req.auth.require(UserCacheData.self)
		// get fez and user to add
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard fez.fezType != .closed else {
			throw Abort(.forbidden, reason: "Cannot add users to closed chat")
		}
		guard fez.fezType != .personalEvent else {
			throw Abort(.forbidden, reason: "Cannot add users to personal events.")
		}
		guard let addingUserID = req.parameters.get(userIDParam.paramString, as: UUID.self),
			let cacheUser = req.userCache.getUser(addingUserID)
		else {
			throw Abort(.forbidden, reason: "invalid user ID in request parameter")
		}
		guard fez.$owner.id == requester.userID else {
			throw Abort(.forbidden, reason: "requester does not own \(fez.fezType.lfgLabel)")
		}
		guard !fez.participantArray.contains(addingUserID) else {
			throw Abort(.badRequest, reason: "user is already in \(fez.fezType.lfgLabel)")
		}
		guard !requester.getBlocks().contains(addingUserID) else {
			throw Abort(.badRequest, reason: "user is not available")
		}
		fez.participantArray.append(addingUserID)
		let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
		let hiddenPostCount = try await fez.$fezPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count()
		let newParticipant = try await getUserPivotForAdd(lfg: fez, userID: addingUserID, on: req.db)
		newParticipant.readCount = 0
		newParticipant.hiddenCount = hiddenPostCount
		try await req.db.transaction { transaction in
			try await fez.save(on: transaction)
			try await newParticipant.save(on: transaction)
		}
		// Tell chat members listening on chat sockets about the new member
		try await forwardMembershipChangeToSockets(fez, participantID: addingUserID, joined: true, on: req)
		// Tell the new member they've been added by the chat owner.
		let infoStr = "@\(requester.username) added you to their \(fez.fezType.lfgLabel) titled \"\(fez.title)\""
		try await addNotifications(users: [addingUserID], type: .addedToChat(fez.requireID(), fez.fezType), info: infoStr, on: req)
		let effectiveUser = getEffectiveUser(user: requester, req: req, fez: fez)
		let requesterPivot = try await fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID).first()
		_ = try await storeNextJoinedAppointment(userID: addingUserID, on: req)
		return try buildFezData(from: fez, with: requesterPivot, for: requester, on: req)
	}

	/// `POST /api/v3/fez/:fezID/user/:userID/remove`
	///
	/// Remove the specified `User` from the specified FriendlyFez. This lets a fez owner remove others.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is not in the barrel. 403 error if requester is not fez
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `FezData` containing the updated fez info.
	func userRemoveHandler(_ req: Request) async throws -> FezData {
		let requester = try req.auth.require(UserCacheData.self)
		// get fez and user to remove
		let removeUser = try await User.findFromParameter(userIDParam, on: req)
		let removeUserID = try removeUser.requireID()
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard fez.fezType != .closed else {
			throw Abort(.forbidden, reason: "Cannot remove users from closed chat")
		}
		guard fez.$owner.id == requester.userID else {
			throw Abort(.forbidden, reason: "requester does not own \(fez.fezType.lfgLabel)")
		}
		guard removeUserID != requester.userID else {
			throw Abort(.forbidden, reason: "Owner cannot remove themselves from \(fez.fezType.lfgLabel)")
		}
		// Save a FezEditRecord containing the participant list before removal
		let fezEdit = try FriendlyFezEdit(fez: fez, editorID: requester.userID)
		try await fezEdit.save(on: req.db)
		// remove user
		guard let index = fez.participantArray.firstIndex(of: removeUserID) else {
			throw Abort(.badRequest, reason: "user is not a member of this \(fez.fezType.lfgLabel)")
		}
		fez.participantArray.remove(at: index)
		try await req.db.transaction { transaction in
			try await fez.save(on: transaction)
			try await fez.$participants.detach(removeUser, on: transaction)
		}
		try await deleteFezNotifications(userIDs: [removeUserID], fez: fez, on: req)
		try await forwardMembershipChangeToSockets(fez, participantID: removeUserID, joined: false, on: req)
		let effectiveUser = getEffectiveUser(user: requester, req: req, fez: fez)
		let pivot = try await fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == effectiveUser.userID).first()
		return try buildFezData(from: fez, with: pivot, for: requester, on: req)
	}

	/// `POST /api/v3/fez/ID/report`
	///
	/// Creates a `Report` regarding the specified `Fez`. This reports on the Fez itself, not any of its posts in particular. This could mean a
	/// Fez with reportable content in its Title, Info, or Location fields, or a bunch of reportable posts in the fez.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter fezID: in URL path, the Fez ID to report.
	/// - Parameter requestBody: `ReportData`
	/// - Returns: 201 Created on success.
	func reportFezHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedFez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		guard reportedFez.fezType != .closed else {
			throw Abort(.forbidden, reason: "Cannot file reports on closed chats")
		}
		guard reportedFez.fezType != .personalEvent else {
			throw Abort(.forbidden, reason: "Cannot file reports on your own personal event")
		}
		return try await reportedFez.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: - Socket Functions

	/// `WS /api/v3/fez/:fezID/socket`
	///
	/// Opens a websocket to receive updates on the given fez. At the moment there's only 2 messages that the client may receive:
	/// - `SocketFezPostData` - sent when a post is added to the fez.
	/// - `SocketMemberChangeData` - sent when a member joins/leaves the fez.
	///
	/// Note that there's a bunch of other state change that can happen with a fez; I haven't built out code to send socket updates for them.
	/// The socket returned by this call is only intended for receiving updates; there are no client-initiated messages defined for this socket.
	/// Posting messages, leaving the fez, updating or canceling the fez and any other state changes should be performed using the various
	/// POST methods of this controller.
	///
	/// The server validates membership before sending out each socket message, but be sure to close the socket if the user leaves the fez.
	/// This method is designed to provide updates only while a user is viewing the fez in your app--don't open one of these sockets for each
	/// fez a user joins and keep them open continually. Use `WS /api/v3/notification/socket` for long-term status updates.
	func createFezSocket(_ req: Request, _ ws: WebSocket) async {
		do {
			let user = try req.auth.require(UserCacheData.self)
			let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
			guard userCanViewMemberData(user: user, fez: fez), let fezID = try? fez.requireID() else {
				throw Abort(.badRequest, reason: "User can't vew messages in this LFG")
			}
			let userSocket = UserSocket(userID: user.userID, socket: ws, fezID: fezID, htmlOutput: false)
			try await req.webSocketStore.storeChatSocket(userSocket)

			ws.onClose.whenComplete { result in
				try? req.webSocketStore.removeChatSocket(userSocket)
			}
		}
		catch {
			try? await ws.close()
		}
	}

	// Checks for sockets open on this fez, and sends the post to each of them.
	func forwardPostToSockets(_ fez: FriendlyFez, _ post: FezPost, on req: Request) async throws {
		let postAuthor = try req.userCache.getHeader(post.$author.id)
		let sockets = try await req.webSocketStore.getChatSockets(fez.requireID())
		for userSocket in sockets {
			guard let socketOwner = req.userCache.getUser(userSocket.userID),
					userCanViewMemberData(user: socketOwner, fez: fez),
					!(socketOwner.getBlocks().contains(postAuthor.userID) || socketOwner.getMutes().contains(postAuthor.userID)) else {
				return
			}
			var leafPost = try SocketFezPostData(post: post, author: postAuthor)
			if userSocket.htmlOutput {
				struct FezPostContext: Encodable {
					var userID: UUID
					var fezPost: SocketFezPostData
					var showModButton: Bool
				}
				let ctx = FezPostContext(userID: userSocket.userID, fezPost: leafPost,
						showModButton: socketOwner.accessLevel.hasAccess(.moderator) && fez.fezType != .closed)
				leafPost.html = try await req.view.render("Fez/fezPost", ctx) .flatMapThrowing { postBuffer -> String? in
					if let data = postBuffer.data.getData(at: 0, length: postBuffer.data.readableBytes),
							let htmlString = String(data: data, encoding: .utf8) {
						return htmlString
					}
					return nil 
				}.get()
			}
			let data = try JSONEncoder().encode(leafPost)
			if let dataString = String(data: data, encoding: .utf8) {
				try await userSocket.socket.send(dataString)
			}
		}
	}

	// Checks for sockets open on this fez, and sends the membership change info to each of them.
	func forwardMembershipChangeToSockets(_ fez: FriendlyFez, participantID: UUID, joined: Bool, on req: Request) async throws
	{
		try await req.webSocketStore.getChatSockets(fez.requireID()).forEach { userSocket in
			let participantHeader = try req.userCache.getHeader(participantID)
			guard let socketOwner = req.userCache.getUser(userSocket.userID),
				userCanViewMemberData(user: socketOwner, fez: fez),
				!socketOwner.getBlocks().contains(participantHeader.userID)
			else {
				return
			}
			var change = SocketFezMemberChangeData(user: participantHeader, joined: joined)
			if userSocket.htmlOutput {
				change.html = "<i>\(participantHeader.username) has \(joined ? "entered" : "left") the chat</i>"
			}
			let data = try JSONEncoder().encode(change)
			if let dataString = String(data: data, encoding: .utf8) {
				userSocket.socket.send(dataString)
			}
		}
	}

	/// `POST /api/v3/fez/:fez_ID/mute`
	///
	/// Mute the specified `Fez` for the current user.
	///
	/// - Parameter fez_ID: In the URL path.
	/// - Returns: 201 Created on success; 200 OK if already muted.
	func muteAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		let effectiveUser = getEffectiveUser(user: cacheUser, req: req, fez: fez)
		guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
			throw Abort(.notFound, reason: "this \(fez.fezType.lfgLabel) is not available")
		}
		// Without this check Moderator A could mute a chat for all Moderators which
		// doesn't feel super good. It's also a confusing UX and would require Help
		// signage to work around. So we're just going to the option to do that.
		guard effectiveUser.userID == cacheUser.userID else {
			throw Abort(.badRequest, reason: "Privileged mailbox chats cannot be muted")
		}
		guard let fezParticipant = try await fez.$participants.$pivots.query(on: req.db)
				.filter(\.$user.$id == effectiveUser.userID).first() else {
			throw Abort(.forbidden, reason: "user is not a member of this fez")
		}

		if fezParticipant.isMuted == true {
			return .ok
		}
		fezParticipant.isMuted = true
		try await fezParticipant.save(on: req.db)
		_ = try await storeNextJoinedAppointment(userID: cacheUser.userID, on: req)
		return .created
	}

	/// `POST /api/v3/fez/:fez_ID/mute/remove`
	/// `DELETE /api/v3/fez/:fez_ID/mute`
	///
	/// Unmute the specified `Fez` for the current user.
	///
	/// - Parameter fez_ID: In the URL path.
	/// - Throws: 400 error if the forum was not muted.
	/// - Returns: 204 No Content on success; 200 OK if already not muted.
	func muteRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		let effectiveUser = getEffectiveUser(user: cacheUser, req: req, fez: fez)
		guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
			throw Abort(.notFound, reason: "this \(fez.fezType.lfgLabel) is not available")
		}
		guard let fezParticipant = try await fez.$participants.$pivots.query(on: req.db)
				.filter(\.$user.$id == effectiveUser.userID).first() else {
			throw Abort(.forbidden, reason: "user is not a member of this fez")
		}

		if fezParticipant.isMuted != true {
			return .ok
		}
		fezParticipant.isMuted = nil
		try await fezParticipant.save(on: req.db)
		_ = try await storeNextJoinedAppointment(userID: cacheUser.userID, on: req)
		return .noContent
	}
}

// MARK: - Helper Functions

extension FezController {

	// This is the bulk of the joinedHandler, pulled out into a separate fn. This allows us to modify the urlQuery arguments
	// before calling.
	func getJoinedChats(_ req: Request, urlQuery: FezURLQueryStruct) async throws -> FezListData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let effectiveUser = try getEffectiveUser(user: cacheUser, req: req)
		let query = FezParticipant.query(on: req.db).filter(\.$user.$id == effectiveUser.userID)
			.join(FriendlyFez.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
		if let includeTypes = try urlQuery.getTypes() {
			query.filter(FriendlyFez.self, \.$fezType ~~ includeTypes)
		}
		else if let excludeTypes = try urlQuery.getExcludeTypes() {
			query.filter(FriendlyFez.self, \.$fezType !~ excludeTypes)
		}

		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let portCalendar = Settings.shared.getPortCalendar()
			if let dayStart = portCalendar.date(byAdding: .day, value: dayFilter, to: Settings.shared.cruiseStartDate()),
					let dayEnd = portCalendar.date(byAdding: DateComponents(day: 1, hour: 3), to: dayStart) {
				query.filter(FriendlyFez.self, \.$endTime >= dayStart).filter(FriendlyFez.self, \.$startTime < dayEnd)
			}
		}

		if urlQuery.hidePast ?? false {
			let searchStartTime = Settings.shared.timeZoneChanges.displayTimeToPortTime().addingTimeInterval(-3600)
			query.filter(FriendlyFez.self, \.$startTime > searchStartTime)
		}

		if let onlyNew = urlQuery.onlynew {
			// Uses a custom filter to test "readCount + hiddenCount < FriendlyFez.postCount". If true, there's unread messages
			// in this chat. Because it uses a custom filter for parameter 1, the other params use the weird long-form notation.
			query.filter(
				DatabaseQuery.Field.custom("\(FezParticipant().$readCount.key) + \(FezParticipant().$hiddenCount.key)"),
				onlyNew ? DatabaseQuery.Filter.Method.lessThan : DatabaseQuery.Filter.Method.equal,
				DatabaseQuery.Field.path(FriendlyFez.path(for: \.$postCount), schema: FriendlyFez.schema)
			)
		}
		if var searchStr = urlQuery.search {
			searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			query.join(FezPost.self, on: \FezPost.$fez.$id == \FriendlyFez.$id, method: .left)
			query.group(.or) { group in
				group.fullTextFilter(FezPost.self, \.$text, searchStr)
					.fullTextFilter(FriendlyFez.self, \.$title, searchStr)
					.fullTextFilter(FriendlyFez.self, \.$info, searchStr)
			}
			// We joined FezPost above, but we need to exclude its fields from the result set to prevent duplicates
			query.fields(for: FezParticipant.self).fields(for: FriendlyFez.self).unique()
		}
		if let matchID = urlQuery.matchID {
			query.filter(\.$id == matchID)
		}
		let fezCount = try await query.count()
		let pivots = try await query.copy().sort(FezParticipant.self, \.$isMuted, .descending)
			.sort(FriendlyFez.self, \.$updatedAt, .descending).range(urlQuery.calcRange()).all()
		let fezDataArray = try pivots.map { pivot -> FezData in
			let fez = try pivot.joined(FriendlyFez.self)
			return try buildFezData(from: fez, with: pivot, for: effectiveUser, on: req)
		}
		return FezListData(paginator: Paginator(total: fezCount, start: urlQuery.calcStart(), limit: urlQuery.calcLimit()),
				fezzes: fezDataArray)
	}

	// This is the bulk of the createHandler, pulled out into a separate fn so we can pass in a custom FezContentData.
	func createChat(_ req: Request, data: FezContentData) async throws -> FezData {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "User cannot create LFGs/Seamails.")
		// see `FezContentData.validations()`
		var creator = user
		if data.createdByTwitarrTeam == true {
			guard user.accessLevel >= .twitarrteam else {
				throw Abort(.badRequest, reason: "Must have TwitarrTeam access to post as @TwitarrTeam")
			}
			guard let ttUser = req.userCache.getUser(username: PrivilegedUser.TwitarrTeam.rawValue) else {
				throw Abort(.internalServerError, reason: "Cannot find @TwitarrTeam user")
			}
			creator = ttUser
		}
		else if data.createdByModerator == true {
			guard user.accessLevel >= .moderator else {
				throw Abort(.badRequest, reason: "Must have moderator access to post as @moderator")
			}
			guard let modUser = req.userCache.getUser(username: PrivilegedUser.moderator.rawValue) else {
				throw Abort(.internalServerError, reason: "Cannot find @moderator user")
			}
			creator = modUser
		}
		// This filters out anyone on the creator's blocklist and any duplicate IDs.
		var creatorBlocks = creator.getBlocks()
		var initialUsers = ([creator.userID] + data.initialUsers).filter { creatorBlocks.insert($0).inserted }
		if creator.userID != user.userID {
			initialUsers = initialUsers.filter { $0 != user.userID }
		}
		guard data.fezType != .closed || initialUsers.count >= 2 else {
			throw Abort(.badRequest, reason: "Fewer than 2 users in seamail after applying user filters")
		}
		guard initialUsers.count >= 1 else {
			throw Abort(.badRequest, reason: "Cannot create \(data.fezType.lfgLabel) with 0 participants")
		}
		let fez = FriendlyFez(owner: creator.userID, fezType: data.fezType, title: data.title, info: data.info,
				location: data.location, startTime: data.startTime, endTime: data.endTime, minCapacity: data.minCapacity,
				maxCapacity: data.maxCapacity)
		fez.participantArray = initialUsers
		try await fez.save(on: req.db)
		let participants = try await User.query(on: req.db).filter(\.$id ~~ initialUsers).all()
		try await fez.$participants.attach(participants, on: req.db,
				{
					$0.readCount = 0
					$0.hiddenCount = 0
				})
		for fezParticipant in fez.participantArray {
			_ = try await storeNextJoinedAppointment(userID: fezParticipant, on: req)
		}
		let addedInitialUsers = Set(initialUsers).subtracting([user.userID, creator.userID])
		let infoStr = "@\(creator.username) added you to their \(fez.fezType.lfgLabel) titled \"\(fez.title)\""
		try await addNotifications(users: Array(addedInitialUsers), type: .addedToChat(fez.requireID(), fez.fezType), info: infoStr, on: req)
		let creatorPivot = try await fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == creator.userID).first()
		let fezData = try buildFezData(from: fez, with: creatorPivot, posts: [], for: user, on: req)
		return fezData
	}
	
	// This is the bulk of updateHandler, which the creator of a chat uses to update the chat's details.
	// For Seamail chats, only the title can be edited after creation. 
	// For all chat types, the particpant list can't be changed with this method; use the add/remove user routes instead.
	// Updating a chat always sets cancelled to false.
	// LFG-type chats can change their type to other LFG types (e.g. "Activity" to "Gaming"). Other chats can't change type.
	func updateChat(_ req: Request, data: FezContentData) async throws -> FezData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get fez
		let fez = try await FriendlyFez.findFromParameter(fezIDParam, on: req)
		try cacheUser.guardCanModifyContent(fez, customErrorString: "User cannot modify LFG")
		guard data.fezType == fez.fezType || (fez.fezType.isLFGType && data.fezType.isLFGType) else {
			throw Abort(.forbidden, reason: "Cannot change the type of a \(fez.fezType.lfgLabel) to \(data.fezType.label)")
		}
		if data.fezType == .personalEvent && !data.initialUsers.isEmpty {
			throw Abort(.forbidden, reason: "Personal Events cannot have other users.")
		}
		if data.title != fez.title || data.location != fez.location || data.info != fez.info {
			let fezEdit = try FriendlyFezEdit(fez: fez, editorID: cacheUser.userID)
			try await fez.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
			try await fezEdit.save(on: req.db)
		}
		fez.fezType = data.fezType
		fez.title = data.title
		fez.info = data.info
		fez.startTime = Settings.shared.timeZoneChanges.serverTimeToPortTime(data.startTime)
		fez.endTime = Settings.shared.timeZoneChanges.serverTimeToPortTime(data.endTime)
		fez.location = data.location
		fez.minCapacity = data.minCapacity
		fez.maxCapacity = data.maxCapacity
		fez.cancelled = false
		try await fez.save(on: req.db)
		for fezParticipant in fez.participantArray {
			_ = try await storeNextJoinedAppointment(userID: fezParticipant, on: req)
		}
		let pivot = try await getUserPivot(lfg: fez, userID: cacheUser.userID, on: req.db)
		return try buildFezData(from: fez, with: pivot, for: cacheUser, on: req)
	}

	// MembersOnlyData is only filled in if:
	//	* The user is a member of the fez (pivot is not nil) OR
	//  * The user is a moderator and the fez is not private
	//
	// Pivot should always be nil if the current user is not a member of the fez.
	// To read the 'moderator' or 'twitarrteam' seamail, verify the requestor has access and call this fn with
	// the effective user's account.
	func buildFezData(from fez: FriendlyFez, with pivot: FezParticipant? = nil, posts: [FezPostData]? = nil,
			for cacheUser: UserCacheData, on req: Request) throws -> FezData {
		let userBlocks = cacheUser.getBlocks()
		// init return struct
		let ownerHeader = try req.userCache.getHeader(fez.$owner.id)
		var fezData: FezData = try FezData(fez: fez, owner: ownerHeader)
		let userIsMember = pivot != nil && pivot?.deletedAt == nil
		if userIsMember || (cacheUser.accessLevel.hasAccess(.moderator) && fez.fezType != .closed) {
			let allParticipantHeaders = req.userCache.getHeaders(fez.participantArray)

			// masquerade blocked users
			let valids = allParticipantHeaders.map { (member: UserHeader) -> UserHeader in
				if userBlocks.contains(member.userID) {
					return UserHeader.Blocked
				}
				return member
			}
			// populate fezData's participant list and waiting list
			var participants: [UserHeader]
			var waitingList: [UserHeader]
			if valids.count > fez.maxCapacity && fez.maxCapacity > 0 {
				participants = Array(valids[valids.startIndex..<fez.maxCapacity])
				waitingList = Array(valids[fez.maxCapacity..<valids.endIndex])
			}
			else {
				participants = valids
				waitingList = []
			}

			// https://github.com/jocosocial/swiftarr/issues/240
			// Moderators can see postCount and readCount regardless of whether they've joined
			// or not. If they have joined, they should get their personal pivot data. If they
			// haven't joined, they shouldn't default to readCount=0 because then every LFG
			// appears with unread messages that cannot be cleared.
			let postCount = fez.postCount - (pivot?.hiddenCount ?? 0)
			fezData.members = FezData.MembersOnlyData(participants: participants, waitingList: waitingList, postCount: postCount,
					readCount: pivot?.readCount ?? postCount, posts: posts, isMuted: pivot?.isMuted ?? false)
		} else if fez.fezType.isPrivateEventType {
			// We need to let non-members see private events they're not currently a member of (so they can report them), but
			// they should only see a minimum amount of info on the event they're not in.
			fezData.info = ""
			fezData.startTime = nil
			fezData.endTime = nil
			fezData.location = nil
		}
		return fezData
	}

	// Remember that there can be posts by authors who are not currently participants.
	func buildPostsForFez(_ fez: FriendlyFez, pivot: FezParticipant?, on req: Request, 
		user: UserCacheData, as effectiveUser: UserCacheData) async throws -> ([FezPostData], Paginator)
	{
		let readCount = pivot?.readCount ?? 0
		let hiddenCount = pivot?.hiddenCount ?? 0
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let start = (req.query[Int.self, at: "start"] ?? ((readCount - 1) / limit) * limit)
			.clamped(to: 0...fez.postCount)
		// get posts
		let posts = try await FezPost.query(on: req.db)
			.filter(\.$fez.$id == fez.requireID())
			.filter(\.$author.$id !~ user.getBlocks())
			.filter(\.$author.$id !~ user.getMutes())
			.sort(\.$createdAt, .ascending)
			.range(start..<(start + limit))
			.all()
		let postDatas = try posts.map { try FezPostData(post: $0, author: req.userCache.getHeader($0.$author.id)) }
		let paginator = Paginator(total: fez.postCount - hiddenCount, start: start, limit: limit)

		// If this batch of posts is farther into the thread than the user has previously read, increase
		// the user's read count.
		if let pivot = pivot, start + limit > pivot.readCount {
			pivot.readCount = min(start + limit, fez.postCount - pivot.hiddenCount)
			try await pivot.save(on: req.db)
			// If the user has now read all the posts (except those hidden from them) mark this notification as viewed.
			if pivot.readCount + pivot.hiddenCount >= fez.postCount {
				try await markNotificationViewed(user: user, type: .chatUnreadMsg(fez.requireID(), fez.fezType), on: req)
				// If the user is part of a privileged mailbox (currently TwitarrTeam and Moderator)
				// the first user to read the message counts it as read for everyone. The pivot
				// has already been updated to reflect this, but a Redis notification will exist
				// until this block executes which will mark the conversation read for all other
				// privileged users of that level.
				if let effectiveUsername = PrivilegedUser(rawValue: effectiveUser.username) {
					var cacheUsers: [UserCacheData] = []
					switch effectiveUsername {
						case .TwitarrTeam: cacheUsers = req.userCache.allUsersWithAccessLevel(.twitarrteam)
						case .moderator: cacheUsers = req.userCache.allUsersWithAccessLevel(.moderator)
						case .admin, .THO: break // No special mailboxes for them.
					}
					// Mark as read for everyone in the group except the current user. We already
					// did that above. Very minor optimization.
					try await markNotificationViewed(for: cacheUsers.filter { $0.userID != user.userID }, type: .chatUnreadMsg(fez.requireID(), fez.fezType), on: req)
				}
			}
		}
		return (postDatas, paginator)
	}

	// Finds the FezParticipant for the given fez and user.
	func getUserPivot(lfg: FriendlyFez, userID: UUID, on db: Database) async throws -> FezParticipant? {
		return try await lfg.$participants.$pivots.query(on: db).filter(\.$user.$id == userID).first()
	}
	
	// Finds or creates a FezParticipant. FezParticipants are soft-deleted and uniqued on user+fez, so we need to check for an existing
	// (soft-deleted) pivot before re-adding a user to an lfg.
	func getUserPivotForAdd(lfg: FriendlyFez, userID: UUID, on db: Database) async throws -> FezParticipant {
		if let result = try await lfg.$participants.$pivots.query(on: db).filter(\.$user.$id == userID).withDeleted().first() {
			try await result.restore(on: db)
			return result
		}
		return try FezParticipant(userID, lfg)
	}

	func userCanViewMemberData(user: UserCacheData, fez: FriendlyFez) -> Bool {
		return user.accessLevel.hasAccess(.moderator) || fez.participantArray.contains(user.userID)
	}

	// For both Moderator and TwittarTeam access levels, there's a special user account with the same name.
	// Seamail to @moderator and @TwitarrTeam may be read by any user with the respective access levels.
	// Instead of designing a new entity for these group inboxes, they're just users that can't log in.
	func getEffectiveUser(user: UserCacheData, req: Request) throws -> UserCacheData {
		guard let effectiveUserParam = req.query[String.self, at: "foruser"] else {
			return user
		}
		var effectiveUser = user
		if effectiveUserParam.lowercased() == PrivilegedUser.moderator.queryParam, let modUser = req.userCache.getUser(username: PrivilegedUser.moderator.rawValue) {
			guard user.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "Only moderators can access moderator seamail.")
			}
			effectiveUser = modUser
		}
		if effectiveUserParam.lowercased() == PrivilegedUser.TwitarrTeam.queryParam, let ttUser = req.userCache.getUser(username: PrivilegedUser.TwitarrTeam.rawValue)
		{
			guard user.accessLevel.hasAccess(.twitarrteam) else {
				throw Abort(.forbidden, reason: "Only TwitarrTeam members can access TwitarrTeam seamail.")
			}
			effectiveUser = ttUser
		}
		return effectiveUser
	}

	// This version of getEffectiveUser checks the user against the fez's membership, and also checks whether
	// user 'moderator' or user 'TwitarrTeam' is a member of the fez and the user has the appropriate access level.
	//
	// Returns `user` unless: @moderator or @TwitarrTeam is a member of the fez and the user has mod (or TT) access.
	func getEffectiveUser(user: UserCacheData, req: Request, fez: FriendlyFez) -> UserCacheData {
		// If either of these 'special' users are fez members and the user has high enough access, we can see the
		// members-only values of the fez as the 'special' user.
		if user.accessLevel >= .twitarrteam, let ttUser = req.userCache.getUser(username: PrivilegedUser.TwitarrTeam.rawValue),
			fez.participantArray.contains(ttUser.userID)
		{
			return ttUser
		}
		if user.accessLevel >= .moderator, let modUser = req.userCache.getUser(username: PrivilegedUser.moderator.rawValue),
			fez.participantArray.contains(modUser.userID)
		{
			return modUser
		}
		// User is or is not a member of the fez. But they are themself and not anyone special.
		return user
	}
}
