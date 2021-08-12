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
        let fezRoutes = app.grouped("api", "v3", "fez")
                
        // endpoints available only when logged in
        let tokenAuthGroup = addTokenAuthGroup(to: fezRoutes)
        tokenAuthGroup.get("joined", use: joinedHandler)
        tokenAuthGroup.get("open", use: openHandler)
        tokenAuthGroup.get("types", use: typesHandler)
        tokenAuthGroup.get(fezIDParam, use: fezHandler)
        tokenAuthGroup.post(fezIDParam, "cancel", use: cancelHandler)
        tokenAuthGroup.post("create", use: createHandler)
        tokenAuthGroup.post(fezIDParam, "join", use: joinHandler)
        tokenAuthGroup.get("owner", use: ownerHandler)
        tokenAuthGroup.post(fezIDParam, "post", use: postAddHandler)
        tokenAuthGroup.post("post", fezPostIDParam, "delete", use: postDeleteHandler)
        tokenAuthGroup.delete("post", fezPostIDParam, use: postDeleteHandler)
        tokenAuthGroup.post(fezIDParam, "unjoin", use: unjoinHandler)
        tokenAuthGroup.post(fezIDParam, "update", use: updateHandler)
        tokenAuthGroup.post("user", userIDParam, "add", use: userAddHandler)
        tokenAuthGroup.post(fezIDParam, "user", userIDParam, "remove", use: userRemoveHandler)
		tokenAuthGroup.post(fezIDParam, "report", use: reportFezHandler)
		tokenAuthGroup.post("post", fezPostIDParam, "report", use: reportFezPostHandler)
        tokenAuthGroup.post(fezIDParam, "delete", use: fezDeleteHandler)
        tokenAuthGroup.delete(fezIDParam, use: fezDeleteHandler)
    }
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    // MARK: Retrieving Fezzes
    
    /// `/GET /api/v3/fez/types`
    ///
    /// Retrieve a list of all values for `FezType` as strings.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[String]` containing the `.label` value for each type.
    func typesHandler(_ req: Request) throws -> EventLoopFuture<[String]> {
        return req.eventLoop.future(FezType.allCases.map { $0.label })
    }
    
    /// `GET /api/v3/fez/open`
    ///
    /// Retrieve all FriendlyFezzes with open slots and a startTime of no earlier than
    /// one hour ago.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `[FezData]` containing all current fezzes with open slots.
    func openHandler(_ req: Request) throws -> EventLoopFuture<[FezData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		let blocked = try req.userCache.getBlocks(user)
		return FriendlyFez.query(on: req.db)
				.filter(\.$fezType != .closed)
				.filter(\.$owner.$id !~ blocked)
				.filter(\.$startTime > Date().addingTimeInterval(-3600))
				.all()
				.flatMapThrowing { (fezzes) in
			return try fezzes.compactMap { fez in
				if (fez.maxCapacity == 0 || fez.participantArray.count < fez.maxCapacity) &&
						!fez.participantArray.contains(userID) {
					return try buildFezData(from: fez, with: nil, for: user, on: req)
				}
				return nil
			}
		}
    }

    /// `GET /api/v3/fez/joined`
    ///
    /// Retrieve all the FriendlyFez chats that the user has joined.
	/// 
	/// Query Parameters:
	/// `?type=STRING` -	Only return fezzes of the given fezType. See `FezType` for a list.
	/// `?excludetype=STRING` - Don't return fezzes of the given type. See `FezType` for a list.
    ///
	/// `/GET /api/v3/fez/types` is  the canonical way to get the list of acceptable values. Type and excludetype are exclusive options, obv.
	///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `[FezData]` containing all the fezzes joined by the user.
    func joinedHandler(_ req: Request) throws -> EventLoopFuture<[FezData]> {
        let user = try req.auth.require(User.self)
        let query = user.$joined_fezzes.$pivots.query(on: req.db)
        		.join(FriendlyFez.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
		if let typeStr = req.query[String.self, at: "type"], let fezType = FezType.fromAPIString(typeStr) {
			query.filter(FriendlyFez.self, \.$fezType == fezType)
		}
		else if let typeStr = req.query[String.self, at: "excludetype"], let fezType = FezType.fromAPIString(typeStr) {
			// excludetype is really only here to exclude .closed fezzes.
			query.filter(FriendlyFez.self, \.$fezType != fezType)
		}
        
        return query.all().flatMapThrowing { pivots in
        	return try pivots.map { pivot in
				let fez = try pivot.joined(FriendlyFez.self)
        		return try buildFezData(from: fez, with: pivot, for: user, on: req)
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
	/// Query Parameters:
	/// `?type=STRING` -	Only return fezzes of the given fezType. See `FezType` for a list.
	/// `?excludetype=STRING` - Don't return fezzes of the given type. See `FezType` for a list.
	///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `[FezData]` containing all the fezzes created by the user.
    func ownerHandler(_ req: Request) throws -> EventLoopFuture<[FezData]> {
        let user = try req.auth.require(User.self)
        let query = try user.$owned_fezzes.query(on: req.db)
        		.join(FezParticipant.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
        		.filter(FezParticipant.self, \.$user.$id == user.requireID())
		if let typeStr = req.query[String.self, at: "type"], let fezType = FezType.fromAPIString(typeStr) {
			query.filter(\.$fezType == fezType)
		}
		else if let typeStr = req.query[String.self, at: "excludetype"], let fezType = FezType.fromAPIString(typeStr) {
			// excludetype is really only here to exclude .closed fezzes.
			query.filter(\.$fezType != fezType)
		}
        // get owned fezzes
        return query.all().flatMapThrowing { fezzes in
			// convert to FezData
			let fezzesData = try fezzes.map { (fez) -> FezData in
				let userParticipant = try fez.joined(FezParticipant.self)
				return try buildFezData(from: fez, with: userParticipant, for: user, on: req)
			}
			return fezzesData
		}
    }
    
    /// `GET /api/v3/fez/ID`
    ///
    /// Retrieve information about the specified FriendlyFez. For users that aren't members of the fez, this info will be the same as 
	/// the info returned for `openHandler`. For users that have joined the fez the `FezData.MembersOnlyData` will be populated, as will
	/// the `FezPost`s. 
	/// 
	/// When a member calls this method, it updates the member's `readCount`, marking all current posts as read.
	/// However, the returned readCount is the value before updating. If there's 5 posts in the chat, and the member has read 3 of them, the returned
	/// `FezData` has 5 posts, we return 3 in `FezData.readCount`field, and update the pivot's readCount to 5.
    ///
    /// - Note: Posts are subject to block and mute user filtering, but mutewords are ignored
    ///   in order to not suppress potentially important information.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if a block between the user and fez owner applies. A 5xx response
    ///   should be reported as a likely bug, please and thank you.
    /// - Returns: `FezDetailData` with fez info and all discussion posts.
    func fezHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        // get fez
        return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
            let cacheUser = try req.userCache.getUser(user)
			guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
				throw Abort(.notFound, reason: "this fez is not available")
			}
			return try fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == user.requireID()).first()
					.throwingFlatMap { pivot in
				var fezData = try buildFezData(from: fez, with: pivot, for: user, on: req)
				if let pivot = pivot {
					return try buildPostsForFez(fez.requireID(), on: req, userBlocks: cacheUser.getBlocks(), 
							userMutes: cacheUser.getMutes()).flatMapThrowing { posts in
						fezData.members?.posts = posts
						//		
						pivot.readCount = posts.count
						pivot.hiddenCount = fez.postCount - posts.count
						_ = pivot.save(on: req.db)
						return fezData
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
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the supplied ID is not a fez barrel or user is already in fez.
    ///   404 error if a block between the user and fez owner applies. A 5xx response should be
    ///   reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez data.
    func joinHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
			guard try !fez.participantArray.contains(user.requireID()) else {
				throw Abort(.notFound, reason: "user is already a member of fez")
			}
			// respect blocks
			let cacheUser = try req.userCache.getUser(user)
			guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
				throw Abort(.notFound, reason: "fez barrel is not available")
			}
			// add user to both the participantArray and attach a pivot for them.
			try fez.participantArray.append(user.requireID())
			let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
			return fez.save(on: req.db).flatMap {
				return fez.$fezPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count().throwingFlatMap { hiddenPostCount in
					let newParticipant = try FezParticipant(user, fez)
					newParticipant.readCount = 0; 
					newParticipant.hiddenCount = hiddenPostCount 
					return newParticipant.save(on: req.db).flatMapThrowing {
						let fezData = try buildFezData(from: fez, with: newParticipant, for: user, on: req)
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
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the supplied ID is not a fez barrel. A 5xx response should be
    ///   reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez data.
    func unjoinHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get fez
        return FriendlyFez.findFromParameter(fezIDParam, on: req).flatMap { (fez) in
			// remove user from participantArray and also remove the pivot.
			if let index = fez.participantArray.firstIndex(of: userID) {
				fez.participantArray.remove(at: index)
			}
			return fez.save(on: req.db)
					.and(fez.$participants.detach(user, on: req.db))
					.flatMapThrowing { (_) in
				return try buildFezData(from: fez, with: nil, for: user, on: req)
			}
		}
	}
	
	// MARK: Posts
	
    /// `POST /api/v3/fez/ID/post`
    ///
    /// Add a `FezPost` to the specified `FriendlyFez`.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically
    /// - Throws: 404 error if the fez is not available. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez discussion.
    func postAddHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        try user.guardCanCreateContent()
        // see PostContentData.validations()
 		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
 		if data.images.count > 1 {
 			throw Abort(.badRequest, reason: "Fez posts may only have one image")
 		}
        // get fez
        return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
            let cacheUser = try req.userCache.getUser(user)
			guard fez.participantArray.contains(cacheUser.userID) else {
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
                let filename = filenames.count > 0 ? filenames[0] : nil
                let post = try FezPost(fez: fez, author: user, text: data.text, image: filename)
                fez.postCount += 1
                var saveFutures = [ post.save(on: req.db), fez.save(on: req.db) ]
                // If any participants block or mute this user, increase their hidden post count as they won't see this post.
                // The nice thing about doing it this way is most of the time there will be no blocks and nothing to do.
				for participantUserID in fez.participantArray {
					if let participantCacheUser = req.userCache.getUser(participantUserID),
							participantCacheUser.getBlocks().contains(cacheUser.userID) || 
							participantCacheUser.getMutes().contains(cacheUser.userID) {
						let incrementHiddenFuture = getUserPivot(fez: fez, userID: participantUserID, on: req.db)
								.flatMap { pivot -> EventLoopFuture<Void> in
							pivot?.hiddenCount += 1
							// Don't fail the add if we can't find the pivot
							return pivot?.save(on: req.db) ?? req.eventLoop.makeSucceededFuture(())
						}
						saveFutures.append(incrementHiddenFuture)		
					}
				}
				return saveFutures.flatten(on: req.eventLoop).throwingFlatMap {
					return try buildPostsForFez(fez.requireID(), on: req, userBlocks: cacheUser.getBlocks(), 
							userMutes: cacheUser.getMutes())
							.and(getUserPivot(fez: fez, userID: cacheUser.userID, on: req.db)).flatMapThrowing { (posts, pivot) in
						// A user posting is assumed to have read all prev posts. (even if this proves untrue, we should increment
						// readCount as they've read the post they just wrote!)
						if let pivot = pivot {
							pivot.readCount = posts.count
							_ = pivot.save(on: req.db)
						}
						let fezData = try buildFezData(from: fez, with: pivot, posts: posts, for: user, on: req)
						let response = Response(status: .created)
						try response.content.encode(fezData)
						return response
					}
				}
			}
		}
	}
						
    /// `POST /api/v3/fez/post/ID/delete`
    ///
    /// Delete a `FezPost`.
    ///
    /// - Parameters: req: The incoming `Request`, provided automatically
    /// - Throws: 403 error if user is not the post author. 404 error if the fez is not
    ///   available. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez discussion.
    func postDeleteHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post
        return FezPost.findFromParameter("post_id", on: req).flatMap { (post) in
			guard post.$author.id == userID else {
				return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot delete post"))
			}
            // get fez and all its participant pivots. Also get count of posts before the one we're deleting.
            return post.$fez.query(on: req.db).with(\.$participants.$pivots).first()
                .unwrap(or: Abort(.internalServerError, reason: "fez not found"))
                .throwingFlatMap { (fez) in
					let cacheUser = try req.userCache.getUser(user)
					guard !cacheUser.getBlocks().contains(fez.$owner.id) else {
						throw Abort(.notFound, reason: "fez is not available")
					}
                	return try fez.$fezPosts.query(on: req.db).filter(\.$id < post.requireID()).count().flatMap { postIndex in
						// delete post, reduce post count cached in fez
						fez.postCount -= 1
						var saveFutures = [ fez.save(on: req.db), post.delete(on: req.db) ]
						var posterPivot: FezParticipant?
						for participantPivot in fez.$participants.pivots {
							if participantPivot.$user.id == userID {
								posterPivot = participantPivot
							}
							// If this user was hiding this post, reduce their hidden count as the post is gone.
							var pivotNeedsSave = false
							if let participantCacheUser = req.userCache.getUser(participantPivot.$user.id),
									participantCacheUser.getBlocks().contains(userID) || 
									participantCacheUser.getMutes().contains(userID) {
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
						}
						
  						post.logIfModeratorAction(.delete, user: user, on: req)
						return saveFutures.flatten(on: req.eventLoop).throwingFlatMap { (_) in
							return try buildPostsForFez(fez.requireID(), on: req, userBlocks: cacheUser.getBlocks(),
									userMutes: cacheUser.getMutes()).flatMapThrowing { posts in
								let fezData = try buildFezData(from: fez, with: posterPivot, posts: posts, for: user, on: req)
								return fezData
							}
						}
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
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
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
    /// - Requires: `FezContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the supplied data does not validate.
    /// - Returns: `FezData` containing the newly created fez.
    func createHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        // see `FezContentData.validations()`
		let data = try ValidatingJSONDecoder().decode(FezContentData.self, fromBodyOf: req)
        let fez = try FriendlyFez(owner: user, fezType: data.fezType, title: data.title, info: data.info,
				location: data.location, startTime: data.startTime, endTime: data.endTime,
				minCapacity: data.minCapacity, maxCapacity: data.maxCapacity)
		var creatorBlocks = try req.userCache.getBlocks(user)
		let initialUsers = (try [user.requireID()] + data.initialUsers).filter { creatorBlocks.insert($0).inserted }
		fez.participantArray = initialUsers
        return fez.save(on: req.db).flatMap { _ in
			return User.query(on: req.db).filter(\.$id ~~ initialUsers).all().flatMap { participants in
				return fez.$participants.attach(participants, on: req.db, { $0.readCount = 0; $0.hiddenCount = 0 }).throwingFlatMap { (_) in
					return try fez.$participants.$pivots.query(on: req.db)
							.filter(\.$user.$id == user.requireID())
							.first()
							.flatMapThrowing() { creatorPivot in
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
    /// Cancel a FriendlyFez.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is not the fez owner. A 5xx response should be
    ///   reported as a likely bug, please and thank you.
    /// - Returns: `FezData` with the updated fez info.
    func cancelHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
			guard try fez.$owner.id == user.requireID() else {
				throw Abort(.forbidden, reason: "user does not own fez")
			}
			// FIXME: this should send out notifications
			fez.cancelled = true
			return fez.save(on: req.db).throwingFlatMap {
				return try fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == user.requireID()).first()
					.flatMapThrowing { pivot in
						return try buildFezData(from: fez, with: pivot, for: user, on: req)
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
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No Content on success.
    func fezDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete a Friendly Fez.")
        }
        return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { fez in
			try user.guardCanModifyContent(fez)
			fez.logIfModeratorAction(.delete, user: user, on: req)
			return fez.delete(on: req.db).transform(to: .noContent)  
        }
    }
	
    /// `POST /api/v3/fez/ID/update`
    ///
    /// Update the specified FriendlyFez with the supplied data.
    ///
    /// - Note: All fields in the supplied `FezContentData` must be filled, just as if the fez
    ///   were being created from scratch. If there is demand, using a set of more efficient
    ///   endpoints instead of this single monolith can be considered.
    ///
    /// - Requires: `FezContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `FezContentData` containing the new fez parameters.
    /// - Throws: 400 error if the data is not valid. 403 error if user is not fez owner.
    ///   A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez info.
    func updateHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		// see FezContentData.validations()
		let data = try ValidatingJSONDecoder().decode(FezContentData.self, fromBodyOf: req)
        // get fez
        return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { (fez) in
            guard fez.$owner.id == userID else {
                 throw Abort(.forbidden, reason: "user does not own fez")
            }
            if data.title != fez.title || data.location != fez.location || data.info != fez.info {
				let fezEdit = try FriendlyFezEdit(fez: fez, editor: user)
				fez.logIfModeratorAction(.edit, user: user, on: req)
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
            return fez.save(on: req.db).throwingFlatMap { (_) in
            	return getUserPivot(fez: fez, userID: userID, on: req.db).flatMapThrowing { pivot in
					return try buildFezData(from: fez, with: pivot, for: user, on: req)
				}
			}
		}
	}
	    
    /// `POST /api/v3/fez/ID/user/ID/add`
    ///
    /// Add the specified `User` to the specified FriendlyFez barrel. This lets a fez owner invite others.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if user is already in barrel. 403 error if requester is not fez
    ///   owner. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez info.
    func userAddHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
        // get fez and user to add
        return FriendlyFez.findFromParameter(fezIDParam, on: req)
				.and(User.findFromParameter(userIDParam, on: req).addModelID())
				.throwingFlatMap { (fez, arg1) in
			let (user, userID) = arg1
			guard fez.$owner.id == requesterID else {
				throw Abort(.forbidden, reason: "requester does not own fez")
			}
			guard !fez.participantArray.contains(userID) else {
				throw Abort(.badRequest, reason: "user is already in fez")
			}
			fez.participantArray.append(userID)
			let cacheUser = try req.userCache.getUser(user)
			let blocksAndMutes = cacheUser.getBlocks().union(cacheUser.getMutes())
			return fez.$fezPosts.query(on: req.db).filter(\.$author.$id ~~ blocksAndMutes).count().flatMap { hiddenPostCount in
				return fez.save(on: req.db).throwingFlatMap { 
					let newParticipant = try FezParticipant(user, fez)
					newParticipant.readCount = 0; 
					newParticipant.hiddenCount = hiddenPostCount 
					return newParticipant.save(on: req.db).flatMapThrowing {
						return try buildFezData(from: fez, with: newParticipant, for: requester, on: req)
					}
				}
			}
        }
    }
    
    /// `POST /api/v3/fez/ID/user/ID/remove`
    ///
    /// Remove the specified `User` from the specified FriendlyFez barrel. This lets a fez owner remove others.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if user is not in the barrel. 403 error if requester is not fez
    ///   owner. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `FezData` containing the updated fez info.
    func userRemoveHandler(_ req: Request) throws -> EventLoopFuture<FezData> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
        // get fez and user to remove
        return FriendlyFez.findFromParameter(fezIDParam, on: req)
				.and(User.findFromParameter(userIDParam, on: req).addModelID())
				.throwingFlatMap { (fez, arg1) in
			let (user, userID) = arg1
			guard fez.$owner.id == requesterID else {
				throw Abort(.forbidden, reason: "requester does not own fez")
			}
			// remove user
			guard let index = fez.participantArray.firstIndex(of: userID) else {
				throw Abort(.badRequest, reason: "user is not in fez")
			}
			fez.participantArray.remove(at: index)
			return fez.save(on: req.db)
				.and(fez.$participants.detach(user, on: req.db))
				.flatMapThrowing { (_) in
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
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Returns: 201 Created on success.
    func reportFezHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let submitter = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)        
		return FriendlyFez.findFromParameter(fezIDParam, on: req).throwingFlatMap { reportedFez in
        	return try reportedFez.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
		}
    }
}


// MARK: - Helper Functions

extension FezController {

	// If pivot is not nil, the FezData's postCount and readCount is filled in. Pivot should always be nil if the current user
	// is not a member of the fez.
	func buildFezData(from fez: FriendlyFez, with pivot: FezParticipant? = nil, posts: [FezPostData]? = nil, for user: User, on req: Request) throws -> FezData {
		let userBlocks = try req.userCache.getBlocks(user)
		// init return struct
		let ownerHeader = try req.userCache.getHeader(fez.$owner.id)
		var fezData : FezData = try FezData(fez: fez, owner: ownerHeader)
		if let pivot = pivot {
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
					postCount: fez.postCount - pivot.hiddenCount, readCount: pivot.readCount, posts: posts)
		}

		return fezData
	}
	
	// Remember that there can be posts by authors who are not currently participants.
	func buildPostsForFez(_ fezID: UUID, on req: Request, userBlocks: Set<UUID> = [], userMutes: Set<UUID> = []) 
			-> EventLoopFuture<[FezPostData]> {
		// get posts
		return FezPost.query(on: req.db)
				.filter(\.$fez.$id == fezID)
				.filter(\.$author.$id !~ userBlocks)
				.filter(\.$author.$id !~ userMutes)
				.sort(\.$createdAt, .ascending)
				.all()
				.flatMapThrowing { (posts) in
			return try posts.map { try FezPostData(post: $0) }
		}
	}
	
	func getUserPivot(fez: FriendlyFez, userID: UUID, on db: Database) -> EventLoopFuture<FezParticipant?> {
		return fez.$participants.$pivots.query(on: db)
				.filter(\.$user.$id == userID)
				.first()
	}


    /// Returns a display string representation of a date stored as a string in either ISO8601
    /// format or as a literal Double.
    ///
    /// - Parameter string: The string representation of the date.
    /// - Returns: String in date format "E, H:mm a", or "TBD" if the string value is "0" or
    ///   the date string is invalid.
    func fezTimeString(from string: String) -> String {
        let dateFormtter = DateFormatter()
        dateFormtter.dateFormat = "E, h:mm a"
        dateFormtter.timeZone = TimeZone(secondsFromGMT: 0)
        switch string {
            case "0":
                return "TBD"
            default:
                if let date = FezController.dateFromParameter(string: string) {
                    return dateFormtter.string(from: date)
                } else {
                    return "TBD"
            }
        }
    }
}
