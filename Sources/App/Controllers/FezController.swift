import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of /api/v3/fez/* route endpoints and handler functions related
/// to FriendlyFez/LFG barrels.

struct FezController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/fez endpoints
		let fezRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .friendlyfez)).grouped("api", "v3", "fez")
	   
		// Open access routes
		fezRoutes.get("types", use: typesHandler)
				
		// endpoints available only when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: fezRoutes)
		tokenCacheAuthGroup.get("open", use: openHandler)
		tokenCacheAuthGroup.get("joined", use: joinedHandler)
		tokenCacheAuthGroup.get("owner", use: ownerHandler)
		tokenCacheAuthGroup.get(fezIDParam, use: fezHandler)
		tokenCacheAuthGroup.post("create", use: createHandler)
		tokenCacheAuthGroup.post(fezIDParam, "post", use: postAddHandler)
 		tokenCacheAuthGroup.webSocket(fezIDParam, "socket", onUpgrade: createFezSocket) 
		tokenCacheAuthGroup.post(fezIDParam, "cancel", use: cancelHandler)
		tokenCacheAuthGroup.post(fezIDParam, "join", use: joinHandler)
		tokenCacheAuthGroup.post(fezIDParam, "unjoin", use: unjoinHandler)
		tokenCacheAuthGroup.post("post", fezPostIDParam, "delete", use: postDeleteHandler)
		tokenCacheAuthGroup.delete("post", fezPostIDParam, use: postDeleteHandler)
		tokenCacheAuthGroup.post(fezIDParam, "user", userIDParam, "add", use: userAddHandler)
		tokenCacheAuthGroup.post(fezIDParam, "user", userIDParam, "remove", use: userRemoveHandler)
		tokenCacheAuthGroup.post(fezIDParam, "update", use: updateHandler)
		tokenCacheAuthGroup.post(fezIDParam, "delete", use: fezDeleteHandler)
		tokenCacheAuthGroup.delete(fezIDParam, use: fezDeleteHandler)

		let tokenAuthGroup = addTokenAuthGroup(to: fezRoutes)
		tokenAuthGroup.post(fezIDParam, "report", use: reportFezHandler)
		tokenAuthGroup.post("post", fezPostIDParam, "report", use: reportFezPostHandler)
 
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
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of <doc:FezData> containing current fezzes with open slots.
	func openHandler(_ req: Request) throws -> EventLoopFuture<FezListData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let futureFezzes = FriendlyFez.query(on: req.db)
				.filter(\.$fezType != .closed)
				.filter(\.$owner.$id !~ cacheUser.getBlocks())
				.filter(\.$cancelled == false)
				.filter(\.$startTime > Date().addingTimeInterval(-3600))
		if let typeFilterStr = req.query[String.self, at: "type"] {
			guard let typeFilter = FezType.fromAPIString(typeFilterStr) else {
				throw Abort(.badRequest, reason: "Could not map 'type' query parameter to FezType.")
			}
			futureFezzes.filter(\.$fezType == typeFilter)
		}
		if let dayFilter = req.query[Int.self, at: "cruiseday"] {
			let dayStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: dayFilter, to: Settings.shared.cruiseStartDate) ??
					Settings.shared.cruiseStartDate
			let dayEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: dayFilter, to: dayStart) ??
					Date()
			futureFezzes.filter(\.$startTime > dayStart).filter(\.$startTime < dayEnd)
		}
		return futureFezzes.count().flatMap { fezCount in
			return futureFezzes.sort(\.$startTime, .ascending).sort(\.$title, .ascending).range(start..<(start + limit))
					.all().flatMapThrowing { fezzes in
				let fezDataArray = try fezzes.compactMap { fez -> FezData? in
					// Fezzes are only 'open' if their waitlist is < 1/2 the size of their capacity. A fez with a max of 10 people
					// could have a waitlist of 5, then it stops showing up in 'open' searches.
					if (fez.maxCapacity == 0 || fez.participantArray.count < Int(Double(fez.maxCapacity) * 1.5)) &&
							!fez.participantArray.contains(cacheUser.userID) {
						return try buildFezData(from: fez, with: nil, for: cacheUser, on: req)
					}
					return nil
				}
				return FezListData(paginator: Paginator(total: fezCount, start: start, limit: limit), fezzes: fezDataArray)
			}
		}
	}

	/// `GET /api/v3/fez/joined`
	///
	/// Retrieve all the FriendlyFez chats that the user has joined. Results are sorted by descending fez update time.
	/// 
	/// **Query Parameters:**
	/// - `?type=STRING` -	Only return fezzes of the given fezType. See `FezType` for a list.
	/// - `?excludetype=STRING` - Don't return fezzes of the given type. See `FezType` for a list.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of fezzes to return; defaults to 50.
	///
	/// `/GET /api/v3/fez/types` is  the canonical way to get the list of acceptable values. Type and excludetype are exclusive options, obv.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of <doc:FezData> containing all the fezzes joined by the user.
	func joinedHandler(_ req: Request) throws -> EventLoopFuture<FezListData> {
		let user = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = FezParticipant.query(on: req.db).filter(\.$user.$id == user.userID)
				.join(FriendlyFez.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
		if let typeStr = req.query[String.self, at: "type"], let fezType = FezType.fromAPIString(typeStr) {
			query.filter(FriendlyFez.self, \.$fezType == fezType)
		}
		else if let typeStr = req.query[String.self, at: "excludetype"], let fezType = FezType.fromAPIString(typeStr) {
			// excludetype is really only here to exclude .closed fezzes.
			query.filter(FriendlyFez.self, \.$fezType != fezType)
		}
		return query.count().flatMap { fezCount in
			return query.sort(FriendlyFez.self, \.$updatedAt, .descending).range(start..<(start + limit)).all().flatMapThrowing { pivots in
				let fezDataArray = try pivots.map { pivot -> FezData in
					let fez = try pivot.joined(FriendlyFez.self)
					return try buildFezData(from: fez, with: pivot, for: user, on: req)
				}
				return FezListData(paginator: Paginator(total: fezCount, start: start, limit: limit), fezzes: fezDataArray)
			}
		}
	}
	
	/// `GET /api/v3/fez/owner`
	///
	/// Retrieve the FriendlyFez barrels created by the user.
	///
	/// - Note: There is no block filtering on this endpoint. In theory, a block could only
	///   apply if it were set *after* the fez had been joined by the second party. The
	///   owner of the fez has the ability to remove users if desired, and the fez itself is no
	///   longer visible to the non-owning party.
	///
	/// **Query Parameters:**
	/// - `?type=STRING` -	Only return fezzes of the given fezType. See `FezType` for a list.
	/// - `?excludetype=STRING` - Don't return fezzes of the given type. See `FezType` for a list.
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of fezzes to return; defaults to 50.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of <doc:FezData> containing all the fezzes created by the user.
	func ownerHandler(_ req: Request) throws -> EventLoopFuture<FezListData> {
		let user = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = FriendlyFez.query(on: req.db).filter(\.$owner.$id == user.userID)
				.join(FezParticipant.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
				.filter(FezParticipant.self, \.$user.$id == user.userID)
		if let typeStr = req.query[String.self, at: "type"], let fezType = FezType.fromAPIString(typeStr) {
			query.filter(\.$fezType == fezType)
		}
		else if let typeStr = req.query[String.self, at: "excludetype"], let fezType = FezType.fromAPIString(typeStr) {
			// excludetype is really only here to exclude .closed fezzes.
			query.filter(\.$fezType != fezType)
		}
		// get owned fezzes
		return query.count().flatMap { fezCount in
			return query.range(start..<(start + limit)).sort(\.$createdAt, .descending).all().flatMapThrowing { fezzes in
				// convert to FezData
				let fezDataArray = try fezzes.map { (fez) -> FezData in
					let userParticipant = try fez.joined(FezParticipant.self)
					return try buildFezData(from: fez, with: userParticipant, for: user, on: req)
				}
				return FezListData(paginator: Paginator(total: fezCount, start: start, limit: limit), fezzes: fezDataArray)
			}
		}
	}
	
	/// `GET /api/v3/fez/ID`
	///
	/// Retrieve information about the specified FriendlyFez. For users that aren't members of the fez, this info will be the same as 
	/// the info returned for `openHandler`. For users that have joined the fez the `FezData.MembersOnlyData` will be populated, as will
	/// the `FezPost`s. 
	/// 
	/// **Query Parameters:**
	/// * `?start=INT` - The offset to the first result to return in the filtered + sorted array of results.
	/// * `?limit=INT` - The maximum number of fezzes to return; defaults to 50.
	/// 
	/// Start and limit only have an effect when the user is a member of the Fez. Limit defaults to 50 and start defaults to `(readCount / limit) * limit`, 
	/// where readCount is how many posts the user has read already.
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
	/// - Returns: <doc:FezData> with fez info and all discussion posts.
	func fezHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get fez
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { fez in
			guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
				throw Abort(.notFound, reason: "this fez is not available")
			}
			return fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first()
					.throwingFlatMap { pivot in
				var fezData = try buildFezData(from: fez, with: pivot, for: cacheUser, on: req)
				if pivot != nil || cacheUser.accessLevel.hasAccess(.moderator) {
					return try buildPostsForFez(fez, pivot: pivot, on: req, user: cacheUser).throwingFlatMap { (posts, paginator) in
						fezData.members?.paginator = paginator
						fezData.members?.posts = posts
						if let pivot = pivot {
							return pivot.save(on: req.db).transform(to: fezData)
						}
						else {
							return req.eventLoop.future(fezData)
						}
					}
				}
				else {
					return req.eventLoop.future(fezData)
				}
			}
		}
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
	/// - Returns: <doc:FezData> containing the updated fez data.
	func joinHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
			guard !fez.participantArray.contains(cacheUser.userID) else {
				throw Abort(.notFound, reason: "user is already a member of this LFG")
			}
			// respect blocks
			guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
				throw Abort(.notFound, reason: "LFG is not available")
			}
			// add user to both the participantArray and attach a pivot for them.
			fez.participantArray.append(cacheUser.userID)
			let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
			return fez.save(on: req.db).flatMap {
				return fez.$fezPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count().throwingFlatMap { hiddenPostCount in
					let newParticipant = try FezParticipant(cacheUser.userID, fez)
					newParticipant.readCount = 0; 
					newParticipant.hiddenCount = hiddenPostCount 
					return newParticipant.save(on: req.db).flatMapThrowing {
						try forwardMembershipChangeToSockets(fez, participantID: cacheUser.userID, joined: true, on: req)
						let fezData = try buildFezData(from: fez, with: newParticipant, for: cacheUser, on: req)
						// return with 201 status
						let response = Response(status: .created)
						try response.content.encode(fezData)
						return response
					}
				}
			}
		}
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
	/// - Returns: <doc:FezData> containing the updated fez data.
	func unjoinHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get fez
		return FriendlyFez.findFromParameter(fezIDParam, on: req).flatMap { fez in
			// remove user from participantArray and also remove the pivot.
			if let index = fez.participantArray.firstIndex(of: cacheUser.userID) {
				fez.participantArray.remove(at: index)
			}
			return fez.save(on: req.db).and(fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).delete())
					.flatMapThrowing { (_) in
				try deleteFezNotifications(userIDs: [cacheUser.userID], fez: fez, on: req)
				try forwardMembershipChangeToSockets(fez, participantID: cacheUser.userID, joined: false, on: req)
				return try buildFezData(from: fez, with: nil, for: cacheUser, on: req)
			}
		}
	}
	
	// MARK: Posts
	
	/// `POST /api/v3/fez/ID/post`
	///
	/// Add a `FezPost` to the specified `FriendlyFez`. 
	/// 
	/// Open fez types are only permitted to have 1 image per post. Private fezzes (aka Seamail) cannot have any images.
	///
	/// - Parameter fezID: in URL path
	/// - Parameter requestBody: <doc:PostContentData> 
	/// - Throws: 404 error if the fez is not available. A 5xx response should be reported
	///   as a likely bug, please and thank you.
	/// - Returns: <doc:FezPostData> containing the user's new post.
	func postAddHandler(_ req: Request) throws -> EventLoopFuture<FezPostData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()
		// see PostContentData.validations()
 		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
 		guard data.images.count <= 1 else {
 			throw Abort(.badRequest, reason: "Fez posts may only have one image")
 		}
		// get fez
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { fez in
			guard fez.participantArray.contains(cacheUser.userID) || cacheUser.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "user is not member of fez; cannot post")
			}
			guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
				throw Abort(.notFound, reason: "fez is not available")
			}
			guard fez.fezType != .closed || data.images.count == 0 else {
				throw Abort(.badRequest, reason: "Private conversations can't contain photos.")
			}
			// process image
			return self.processImages(data.images , usage: .fezPost, on: req).throwingFlatMap { (filenames) in
				// create and save the new post, update fezzes' cached post count
				let effectiveAuthor = data.effectiveAuthor(actualAuthor: cacheUser, on: req)
				let filename = filenames.count > 0 ? filenames[0] : nil
				let post = try FezPost(fez: fez, authorID: effectiveAuthor.userID, text: data.text, image: filename)
				fez.postCount += 1
				var saveFutures = [ post.save(on: req.db), fez.save(on: req.db) ]
				// If any participants block or mute this user, increase their hidden post count as they won't see this post.
				// The nice thing about doing it this way is most of the time there will be no blocks and nothing to do.
				var participantNotifyList: [UUID] = []
				for participantUserID in fez.participantArray {
					guard let participantCacheUser = req.userCache.getUser(participantUserID) else {
						continue
					}
					if participantCacheUser.getBlocks().contains(effectiveAuthor.userID) || 
							participantCacheUser.getMutes().contains(effectiveAuthor.userID) {
						let incrementHiddenFuture = getUserPivot(fez: fez, userID: participantUserID, on: req.db)
								.flatMap { pivot -> EventLoopFuture<Void> in
							pivot?.hiddenCount += 1
							// Don't fail the add if we can't find the pivot
							return pivot?.save(on: req.db) ?? req.eventLoop.makeSucceededFuture(())
						}
						saveFutures.append(incrementHiddenFuture)		
					}
					else if participantUserID != cacheUser.userID {
						participantNotifyList.append(participantUserID)
					}
				}
				return saveFutures.flatten(on: req.eventLoop).throwingFlatMap {
					var infoStr = "@\(effectiveAuthor.username) wrote, \"\(post.text)\""
					if fez.fezType != .closed {
						infoStr.append(" in LFG \"\(fez.title)\".")
					}
					try addNotifications(users: participantNotifyList, type: fez.notificationType(), info: infoStr, on: req)
					try forwardPostToSockets(fez, post, on: req)
					return getUserPivot(fez: fez, userID: cacheUser.userID, on: req.db).flatMapThrowing { pivot in
						// A user posting is assumed to have read all prev posts. (even if this proves untrue, we should increment
						// readCount as they've read the post they just wrote!)
						if let pivot = pivot {
							pivot.readCount = fez.postCount - pivot.hiddenCount
							_ = pivot.save(on: req.db)
						}
						return try FezPostData(post: post, author: effectiveAuthor.makeHeader())
					}
				}
			}
		}
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
	func postDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get post
		return FezPost.findFromParameter(fezPostIDParam, on: req).throwingFlatMap { post in
			try cacheUser.guardCanModifyContent(post)
			// get fez and all its participant pivots. Also get count of posts before the one we're deleting.
			return post.$fez.query(on: req.db).with(\.$participants.$pivots).first()
					.unwrap(or: Abort(.internalServerError, reason: "LFG not found"))
					.throwingFlatMap { fez in
				guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
					throw Abort(.notFound, reason: "LFG is not available")
				}
				return try fez.$fezPosts.query(on: req.db).filter(\.$id < post.requireID()).count().throwingFlatMap { postIndex in
					// delete post, reduce post count cached in fez
					fez.postCount -= 1
					var saveFutures = [ fez.save(on: req.db), post.delete(on: req.db) ]
					var adjustNotificationCountForUsers: [UUID] = []
					for participantPivot in fez.$participants.pivots {
						// If this user was hiding this post, reduce their hidden count as the post is gone.
						var pivotNeedsSave = false
						if let participantCacheUser = req.userCache.getUser(participantPivot.$user.id),
								participantCacheUser.getBlocks().contains(cacheUser.userID) || 
								participantCacheUser.getMutes().contains(cacheUser.userID) {
							participantPivot.hiddenCount = max(participantPivot.hiddenCount - 1, 0)
							pivotNeedsSave = true
						}
						// If the user has read the post being deleted, reduce their read count by 1.
						if participantPivot.readCount > postIndex {
							participantPivot.readCount -= 1
							pivotNeedsSave = true
						}
						if pivotNeedsSave {
							saveFutures.append(participantPivot.save(on: req.db))
						}
						else if participantPivot.$user.id != cacheUser.userID {
							adjustNotificationCountForUsers.append(participantPivot.$user.id)
						}
					}
					_ = try subtractNotifications(users: adjustNotificationCountForUsers, type: fez.notificationType(), on: req)
					post.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
					return saveFutures.flatten(on: req.eventLoop).transform(to: .noContent)
				}
			}
		}
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
	/// - Parameter requestBody: <doc:ReportData> payload in the HTTP body.
	/// - Returns: 201 Created on success.
	func reportFezPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let submitter = try req.auth.require(User.self)
		let data = try req.content.decode(ReportData.self)		
		return FezPost.findFromParameter(fezPostIDParam, on: req).throwingFlatMap { reportedPost in
			return try reportedPost.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
		}
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
	/// - Parameter requestBody: <doc:FezContentData> payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: <doc:FezData> containing the newly created fez.
	func createHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		let user = try req.auth.require(UserCacheData.self)
		// see `FezContentData.validations()`
		let data = try ValidatingJSONDecoder().decode(FezContentData.self, fromBodyOf: req)
		let fez = FriendlyFez(owner: user.userID, fezType: data.fezType, title: data.title, info: data.info,
				location: data.location, startTime: data.startTime, endTime: data.endTime,
				minCapacity: data.minCapacity, maxCapacity: data.maxCapacity)
		// This filters out anyone on the creator's blocklist and any duplicate IDs.
		var creatorBlocks = user.getBlocks()
		let initialUsers = ([user.userID] + data.initialUsers).filter { creatorBlocks.insert($0).inserted }
		fez.participantArray = initialUsers
		return fez.save(on: req.db).flatMap { _ in
			return User.query(on: req.db).filter(\.$id ~~ initialUsers).all().flatMap { participants in
				return fez.$participants.attach(participants, on: req.db, { $0.readCount = 0; $0.hiddenCount = 0 }).throwingFlatMap { (_) in
					return fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == user.userID)
							.first().flatMapThrowing() { creatorPivot in
						let fezData = try buildFezData(from: fez, with: creatorPivot, posts: [], for: user, on: req)
						// with 201 status
						let response = Response(status: .created)
						try response.content.encode(fezData)
						return response
					}
				}
			}
		}
	}
		
	/// `POST /api/v3/fez/ID/cancel`
	///
	/// Cancel a FriendlyFez. Owner only. Cancelling a Fez is different from deleting it. A canceled fez is still visible; members may still post to it.
	/// But, a cenceled fez does not show up in searches for open fezzes, and should be clearly marked in UI to indicate that it's been canceled.
	/// 
	/// - Note: Eventually, cancelling a fez should notifiy all members via the notifications endpoint.
	///
	/// - Parameter fezID: in URL path.
	/// - Throws: 403 error if user is not the fez owner. A 5xx response should be
	///   reported as a likely bug, please and thank you.
	/// - Returns: <doc:FezData> with the updated fez info.
	func cancelHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
			guard fez.$owner.id == cacheUser.userID else {
				throw Abort(.forbidden, reason: "user does not own fez")
			}
			// FIXME: this should send out notifications
			fez.cancelled = true
			return fez.save(on: req.db).throwingFlatMap {
				return fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first()
					.flatMapThrowing { pivot in
						return try buildFezData(from: fez, with: pivot, for: cacheUser, on: req)
				}
			}
		}
	}
		
	/// `POST /api/v3/fez/ID/delete`
	/// `DELETE /api/v3/fez/ID`
	///
	/// Delete the specified `FriendlyFez`. This soft-deletes the fez. Posts are left as-is. 
	/// 
	/// To delete, the user must have an access level allowing them to delete the fez. Currently this means moderators and above. 
	/// The owner of a fez may Cancel the fez, which tells the members the fez was cancelled, but does not delete it.
	///
	/// - Parameter fezID: in URL path.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func fezDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete an LFG.")
		}
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { fez in
			try cacheUser.guardCanModifyContent(fez)
	   		try deleteFezNotifications(userIDs: fez.participantArray, fez: fez, on: req)
			fez.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
			return fez.$participants.detachAll(on: req.db).flatMap { _ in
				return fez.delete(on: req.db).transform(to: .noContent)
			}
		}
	}
	
	/// `POST /api/v3/fez/ID/update`
	///
	/// Update the specified FriendlyFez with the supplied data. Updating a cancelled fez will un-cancel it.
	///
	/// - Note: All fields in the supplied `FezContentData` must be filled, just as if the fez
	///   were being created from scratch. If there is demand, using a set of more efficient
	///   endpoints instead of this single monolith can be considered.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter requestBody: <doc:FezContentData> payload in the HTTP body.
	/// - Throws: 400 error if the data is not valid. 403 error if user is not fez owner.
	///   A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:FezData> containing the updated fez info.
	func updateHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// see FezContentData.validations()
		let data = try ValidatingJSONDecoder().decode(FezContentData.self, fromBodyOf: req)
		// get fez
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { fez in
			try cacheUser.guardCanModifyContent(fez, customErrorString: "User cannot modify LFG")
			if data.title != fez.title || data.location != fez.location || data.info != fez.info {
				let fezEdit = try FriendlyFezEdit(fez: fez, editorID: cacheUser.userID)
				fez.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
				let _ = fezEdit.save(on: req.db)
			}
			fez.fezType = data.fezType
			fez.title = data.title
			fez.info = data.info
			fez.startTime = data.startTime
			fez.endTime = data.endTime
			fez.location = data.location
			fez.minCapacity = data.minCapacity
			fez.maxCapacity = data.maxCapacity
			fez.cancelled = false
			return fez.save(on: req.db).throwingFlatMap { (_) in
				return getUserPivot(fez: fez, userID: cacheUser.userID, on: req.db).flatMapThrowing { pivot in
					return try buildFezData(from: fez, with: pivot, for: cacheUser, on: req)
				}
			}
		}
	}
		
	/// `POST /api/v3/fez/ID/user/ID/add`
	///
	/// Add the specified `User` to the specified FriendlyFez barrel. This lets a fez owner invite others.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is already in barrel. 403 error if requester is not fez
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:FezData> containing the updated fez info.
	func userAddHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
		let requester = try req.auth.require(UserCacheData.self)
		// get fez and user to add
		return FriendlyFez.findFromParameter(fezIDParam, on: req)
				.and(User.findFromParameter(userIDParam, on: req).addModelID())
				.throwingFlatMap { (fez, arg1) in
			let (user, userID) = arg1
			guard fez.$owner.id == requester.userID else {
				throw Abort(.forbidden, reason: "requester does not own LFG")
			}
			guard !fez.participantArray.contains(userID) else {
				throw Abort(.badRequest, reason: "user is already in LFG")
			}
			guard !requester.getBlocks().contains(userID) else {
				throw Abort(.badRequest, reason: "user is not available")
			}
			fez.participantArray.append(userID)
			let cacheUser = try req.userCache.getUser(user)
			let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
			return fez.$fezPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count().flatMap { hiddenPostCount in
				return fez.save(on: req.db).throwingFlatMap { 
					let newParticipant = try FezParticipant(userID, fez)
					newParticipant.readCount = 0; 
					newParticipant.hiddenCount = hiddenPostCount 
					return newParticipant.save(on: req.db).flatMapThrowing {
						try forwardMembershipChangeToSockets(fez, participantID: userID, joined: true, on: req)
						return try buildFezData(from: fez, with: newParticipant, for: requester, on: req)
					}
				}
			}
		}
	}
	
	/// `POST /api/v3/fez/ID/user/:userID/remove`
	///
	/// Remove the specified `User` from the specified FriendlyFez barrel. This lets a fez owner remove others.
	///
	/// - Parameter fezID: in URL path.
	/// - Parameter userID: in URL path.
	/// - Throws: 400 error if user is not in the barrel. 403 error if requester is not fez
	///   owner. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:FezData> containing the updated fez info.
	func userRemoveHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
		let requester = try req.auth.require(UserCacheData.self)
		// get fez and user to remove
		return FriendlyFez.findFromParameter(fezIDParam, on: req)
				.and(User.findFromParameter(userIDParam, on: req).addModelID())
				.throwingFlatMap { (fez, arg1) in
			let (user, userID) = arg1
			guard fez.$owner.id == requester.userID else {
				throw Abort(.forbidden, reason: "requester does not own fez")
			}
			// remove user
			guard let index = fez.participantArray.firstIndex(of: userID) else {
				throw Abort(.badRequest, reason: "user is not in fez")
			}
			fez.participantArray.remove(at: index)
			return fez.save(on: req.db).and(fez.$participants.detach(user, on: req.db)).flatMapThrowing { (_) in
				try deleteFezNotifications(userIDs: [userID], fez: fez, on: req)
				try forwardMembershipChangeToSockets(fez, participantID: userID, joined: false, on: req)
				return try buildFezData(from: fez, with: nil, for: requester, on: req)
			}
		}
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
	/// - Parameter requestBody: <doc:ReportData>
	/// - Returns: 201 Created on success.
	func reportFezHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let submitter = try req.auth.require(User.self)
		let data = try req.content.decode(ReportData.self)		
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { reportedFez in
			return try reportedFez.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
		}
	}

// MARK: - Socket Functions

	/// `WS /api/v3/fez/:fezID/socket`
	/// 
	/// Opens a websocket to receive updates on the given fez. At the moment there's only 2 messages that the client may receive:
	/// - <doc:SocketFezPostData> - sent when a post is added to the fez.
	/// - <doc:SocketMemberChangeData> - sent when a member joins/leaves the fez.
	/// 
	/// Note that there's a bunch of other state change that can happen with a fez; I haven't built out code to send socket updates for them.
	/// The socket returned by this call is only intended for receiving updates; there are no client-initiated messages defined for this socket.
	/// Posting messages, leaving the fez, updating or canceling the fez and any other state changes should be performed using the various
	/// POST methods of this controller.
	/// 
	/// The server validates membership before sending out each socket message, but be sure to close the socket if the user leaves the fez.
	/// This method is designed to provide updates only while a user is viewing the fez in your app--don't open one of these sockets for each
	/// fez a user joins and keep them open continually. Use `WS /api/v3/notification/socket` for long-term status updates.
	func createFezSocket(_ req: Request, _ ws: WebSocket) {
		guard let user = try? req.auth.require(UserCacheData.self) else {
			_ = ws.close()
			return
		}
		_ = FriendlyFez.findFromParameter(fezIDParam, on: req).map { fez in
			guard userCanViewMemberData(user: user, fez: fez), let fezID = try? fez.requireID() else {
				_ = ws.close()
				return
			}
			let userSocket = UserSocket(userID: user.userID, socket: ws, fezID: fezID, htmlOutput: false)
			try? req.webSocketStore.storeFezSocket(userSocket)

			ws.onClose.whenComplete { result in
				try? req.webSocketStore.removeFezSocket(userSocket)
			}
		}
	}

	// Checks for sockets open on this fez, and sends the post to each of them.
	func forwardPostToSockets(_ fez: FriendlyFez, _ post: FezPost, on req: Request) throws {
		try req.webSocketStore.getFezSockets(fez.requireID()).forEach { userSocket in
			let postAuthor = try req.userCache.getHeader(post.$author.id)
			guard let socketOwner = req.userCache.getUser(userSocket.userID), userCanViewMemberData(user: socketOwner, fez: fez),
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
				_ = req.view.render("Fez/fezPost", ctx).flatMapThrowing { postBuffer in
					if let data = postBuffer.data.getData(at: 0, length: postBuffer.data.readableBytes),
							let htmlString = String(data: data, encoding: .utf8) {
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

	// Checks for sockets open on this fez, and sends the membership change info to each of them.
	func forwardMembershipChangeToSockets(_ fez: FriendlyFez, participantID: UUID, joined: Bool, on req: Request) throws {
		try req.webSocketStore.getFezSockets(fez.requireID()).forEach { userSocket in
			let participantHeader = try req.userCache.getHeader(participantID)
			guard let socketOwner = req.userCache.getUser(userSocket.userID), userCanViewMemberData(user: socketOwner, fez: fez),
					!socketOwner.getBlocks().contains(participantHeader.userID) else {
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
}

// MARK: - Helper Functions

extension FezController {

	// If pivot is not nil, the FezData's postCount and readCount is filled in. Pivot should always be nil if the current user
	// is not a member of the fez.
	func buildFezData(from fez: FriendlyFez, with pivot: FezParticipant? = nil, posts: [FezPostData]? = nil, 
			for cacheUser: UserCacheData, on req: Request) throws -> FezData {
		let userBlocks = cacheUser.getBlocks()
		// init return struct
		let ownerHeader = try req.userCache.getHeader(fez.$owner.id)
		var fezData : FezData = try FezData(fez: fez, owner: ownerHeader)
		if pivot != nil || cacheUser.accessLevel.hasAccess(.moderator) {
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
			fezData.members = FezData.MembersOnlyData(participants: participants, waitingList: waitingList, 
					postCount: fez.postCount - (pivot?.hiddenCount ?? 0), readCount: pivot?.readCount ?? 0, posts: posts)
		}
		return fezData
	}
	
	// Remember that there can be posts by authors who are not currently participants.
	func buildPostsForFez(_ fez: FriendlyFez, pivot: FezParticipant?, on req: Request, user: UserCacheData) throws
			-> EventLoopFuture<([FezPostData], Paginator)> {
		let readCount = pivot?.readCount ?? 0
		let hiddenCount = pivot?.hiddenCount ?? 0
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let start = (req.query[Int.self, at: "start"] ?? ((readCount - 1) / limit) * limit)
				.clamped(to: 0...fez.postCount)
		// get posts
		return try FezPost.query(on: req.db)
				.filter(\.$fez.$id == fez.requireID())
				.filter(\.$author.$id !~ user.getBlocks())
				.filter(\.$author.$id !~ user.getMutes())
				.sort(\.$createdAt, .ascending)
				.range(start..<(start + limit))
				.all()
				.flatMapThrowing { (posts) in
			let posts = try posts.map { try FezPostData(post: $0, author: req.userCache.getHeader($0.$author.id)) }
			let paginator = Paginator(total: fez.postCount - hiddenCount, start: start, limit: limit)
			
			// If this batch of posts is farther into the thread than the user has previously read, increase
			// the user's read count.
			if let pivot = pivot, start + limit > pivot.readCount {
				pivot.readCount = min(start + limit, fez.postCount - pivot.hiddenCount)
				_ = pivot.save(on: req.db)
				// If the user has now read all the posts (except those hidden from them) mark this notification as viewed.
				if pivot.readCount + pivot.hiddenCount >= fez.postCount {
					try markNotificationViewed(userID: user.userID, type: fez.notificationType(), on: req)
				}
			}
			return (posts, paginator)
		}
	}
	
	func getUserPivot(fez: FriendlyFez, userID: UUID, on db: Database) -> EventLoopFuture<FezParticipant?> {
		return fez.$participants.$pivots.query(on: db)
				.filter(\.$user.$id == userID)
				.first()
	}

	func userCanViewMemberData(user: UserCacheData, fez: FriendlyFez) -> Bool {
		return user.accessLevel.hasAccess(.moderator) || fez.participantArray.contains(user.userID) 
	}
}
